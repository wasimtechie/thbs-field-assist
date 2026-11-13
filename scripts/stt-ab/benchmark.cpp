// Local-only diagnostic: no network, authentication, microphone or report APIs.
// Phonon call sequence follows its published phonon2.h / Android integration note.
#include "phonon2.h"
#include "moonshine-c-api.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <complex>
#include <cstring>
#include <dlfcn.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <sys/resource.h>
#include <thread>
#include <vector>
#include <arm_neon.h>
#ifdef __ANDROID__
#include <sys/auxv.h>
#include <asm/hwcap.h>
#endif

using Clock = std::chrono::steady_clock;
double ms(Clock::time_point t) { return std::chrono::duration<double, std::milli>(Clock::now()-t).count(); }
void require(bool ok, const std::string& why) { if(!ok) throw std::runtime_error(why); }
template<class T> T read(std::istream& f) { T t{}; f.read(reinterpret_cast<char*>(&t),sizeof(t)); require(bool(f),"Truncated benchmark data"); return t; }
std::string str(std::istream& f) { auto n=read<uint32_t>(f); require(n<1048576,"Invalid string length"); std::string s(n,'\0'); f.read(s.data(),n);require(bool(f),"Truncated string");return s; }
std::string quote(const std::string& s) { std::ostringstream o;o<<'"';for(unsigned char c:s){if(c=='"'||c=='\\')o<<'\\'<<c;else if(c=='\n')o<<"\\n";else if(c<32)o<<" ";else o<<c;}o<<'"';return o.str(); }
void* library(const std::string& p) { auto h=dlopen(p.c_str(),RTLD_NOW|RTLD_LOCAL);require(h!=nullptr,std::string("Cannot load ")+p+": "+(h?"":dlerror()));return h; }
template<class T> T symbol(void* h,const char* n){auto p=dlsym(h,n);require(p!=nullptr,std::string("Missing native symbol: ")+n);return reinterpret_cast<T>(p);}
std::string phononLibrary(const std::string& dir,const std::string& name){
#ifdef __ANDROID__
 auto features=getauxval(AT_HWCAP);bool optimized=(features&HWCAP_ASIMDDP)&&(features&HWCAP_ATOMICS);
 return dir+"/"+name+(optimized?"":"-base");
#else
 return dir+"/"+name;
#endif
}
struct Tensor { uint32_t kind=0,rows=0,cols=0;std::vector<uint8_t> data;const float* f()const{return reinterpret_cast<const float*>(data.data());}const uint16_t* h()const{return reinterpret_cast<const uint16_t*>(data.data());} };

#define ENC_NAMES(X) X(phonon2_cpu_abi_version) X(phonon2_enc_abi_version) X(phonon2_cpu_features) X(phonon2_cpu_build_features) X(phonon2_cpu_kernel_in_use) X(phonon2_cpu_set_threads) X(phonon2_cpu_create_onedot_wire) X(phonon2_cpu_destroy) X(phonon2_enc_create) X(phonon2_enc_destroy) X(phonon2_enc_set_subsampling) X(phonon2_enc_set_layer) X(phonon2_enc_out_len) X(phonon2_enc_forward)
#define TDT_NAMES(X) X(phonon2_tdt_create) X(phonon2_tdt_destroy) X(phonon2_tdt_set_threads) X(phonon2_tdt_decode_timed) X(phonon2_tdt_set_bias)
#define DECLARE(n) decltype(&::n) n;
struct EncoderAPI { ENC_NAMES(DECLARE) void* handle;
 explicit EncoderAPI(const std::string& p):handle(library(p)){
#define RESOLVE(n) n=symbol<decltype(n)>(handle,#n);
 ENC_NAMES(RESOLVE)
#undef RESOLVE
 }};
struct DecoderAPI { TDT_NAMES(DECLARE) void* handle;
 explicit DecoderAPI(const std::string& p):handle(library(p)){
#define RESOLVE(n) n=symbol<decltype(n)>(handle,#n);
 TDT_NAMES(RESOLVE)
#undef RESOLVE
 }};
#undef DECLARE
struct Timing { double frontend=0,encoder=0,projector=0,decoder=0,finalize=0; };

struct Phonon {
 EncoderAPI e;DecoderAPI d;void* enc=nullptr;void* dec=nullptr;
 std::map<std::string,Tensor> tensors;std::vector<void*> matrices;std::vector<std::string> vocab;
 bool hinted;int kernel=0;
 Phonon(const std::string& root,const std::string& lib,int threads,bool hints):e(phononLibrary(lib,"enc")),d(phononLibrary(lib,"tdt")),hinted(hints){
  require(e.phonon2_cpu_abi_version()==1&&e.phonon2_enc_abi_version()==1,"Phonon encoder ABI mismatch");
  require((e.phonon2_cpu_build_features()&~e.phonon2_cpu_features())==0,"Native library assumes unsupported CPU instructions");
  e.phonon2_cpu_set_threads(threads);d.phonon2_tdt_set_threads(threads);
  std::ifstream f(root+"/phonon-tensors.bin",std::ios::binary);char magic[8];f.read(magic,8);require(std::string(magic,8)=="STTAB001","Tensor bundle version mismatch");auto count=read<uint32_t>(f);require(count<2000,"Invalid tensor count");
  std::map<std::string,void*> packed;
  for(uint32_t j=0;j<count;j++){
   auto name=str(f);Tensor t;t.kind=read<uint32_t>(f);t.rows=read<uint32_t>(f);t.cols=read<uint32_t>(f);auto n=read<uint64_t>(f);require(n<100000000,"Oversize tensor");auto at=uint64_t(f.tellg());f.seekg((16-at%16)%16,std::ios::cur);t.data.resize(n);f.read(reinterpret_cast<char*>(t.data.data()),n);require(bool(f),"Truncated tensor");
   if(t.kind==1){auto p=e.phonon2_cpu_create_onedot_wire(t.rows,t.cols,t.data.data(),n);require(p!=nullptr,"Cannot create packed matrix "+name);packed[name]=p;matrices.push_back(p);}else tensors.emplace(name,std::move(t));
  }
  require(!f.bad(),"Cannot read tensor bundle");
  auto F=[&](const std::string& n){return tensors.at(n).f();};
  enc=e.phonon2_enc_create(24,1024,4096,8,9,128,256);require(enc!=nullptr,"Cannot create encoder");
  std::string S="encoder.subsampling.";
  require(e.phonon2_enc_set_subsampling(enc,F(S+"layers.0.weight"),F(S+"layers.0.bias"),F(S+"layers.2.weight"),F(S+"layers.2.bias"),F(S+"layers.3.weight"),F(S+"layers.3.bias"),F(S+"layers.5.weight"),F(S+"layers.5.bias"),F(S+"layers.6.weight"),F(S+"layers.6.bias"),F(S+"linear.weight"),F(S+"linear.bias"),F("inv_freq"))==0,"Subsampling setup failed");
  const std::array<std::string,11> M={"feed_forward1.linear1","feed_forward1.linear2","self_attn.q_proj","self_attn.k_proj","self_attn.v_proj","self_attn.o_proj","self_attn.relative_k_proj","conv.pointwise_conv1","conv.pointwise_conv2","feed_forward2.linear1","feed_forward2.linear2"};
  const std::array<std::string,17> V={"norm_feed_forward1.weight","norm_feed_forward1.bias","norm_self_att.weight","norm_self_att.bias","norm_conv.weight","norm_conv.bias","norm_feed_forward2.weight","norm_feed_forward2.bias","norm_out.weight","norm_out.bias","self_attn.bias_u","self_attn.bias_v","conv.depthwise_conv.weight","conv.norm.weight","conv.norm.bias","conv.norm.running_mean","conv.norm.running_var"};
  for(int l=0;l<24;l++){std::string p="encoder.layers."+std::to_string(l)+".";void* a[11];const float* b[17];for(int i=0;i<11;i++)a[i]=packed.at(p+M[i]);for(int i=0;i<17;i++)b[i]=F(p+V[i]);require(e.phonon2_enc_set_layer(enc,l,a,b)==0,"Layer setup failed");}
  auto Q=[&](const std::string& n){return reinterpret_cast<const int8_t*>(tensors.at(n+".q").data.data());};auto H=[&](const std::string& n){return tensors.at(n).h();};int durations[]={0,1,2,3,4};
  dec=d.phonon2_tdt_create(8193,640,640,8198,5,durations,8192,10,Q("decoder.embedding.weight"),H("decoder.embedding.weight.s"),Q("decoder.lstm.weight_ih_l0"),H("decoder.lstm.weight_ih_l0.s"),H("decoder.lstm.bias_ih_l0.h"),Q("decoder.lstm.weight_hh_l0"),H("decoder.lstm.weight_hh_l0.s"),H("decoder.lstm.bias_hh_l0.h"),Q("decoder.lstm.weight_ih_l1"),H("decoder.lstm.weight_ih_l1.s"),H("decoder.lstm.bias_ih_l1.h"),Q("decoder.lstm.weight_hh_l1"),H("decoder.lstm.weight_hh_l1.s"),H("decoder.lstm.bias_hh_l1.h"),Q("decoder.decoder_projector.weight"),H("decoder.decoder_projector.weight.s"),H("decoder.decoder_projector.bias.h"),Q("joint.head.weight"),H("joint.head.weight.s"),H("joint.head.bias.h"));require(dec!=nullptr,"Decoder setup failed");
  if(hints){auto& t=tensors.at("bias.table");auto& c=tensors.at("bias.col");require(d.phonon2_tdt_set_bias(dec,t.rows,t.cols,reinterpret_cast<const int32_t*>(t.data.data()),reinterpret_cast<const int32_t*>(tensors.at("bias.toks").data.data()),reinterpret_cast<const int32_t*>(c.data.data()),c.rows,reinterpret_cast<const int32_t*>(tensors.at("bias.depth").data.data()),2)==0,"Hotword setup failed");}
  for(auto it=tensors.begin();it!=tensors.end();){const auto& n=it->first;if(n=="window"||n=="mel_filters"||n.rfind("bias.",0)==0||n.rfind("encoder_projector.",0)==0)++it;else it=tensors.erase(it);}
  std::ifstream vf(root+"/vocabulary.bin",std::ios::binary);auto nv=read<uint32_t>(vf);require(nv==8192,"Vocabulary mismatch");for(uint32_t i=0;i<nv;i++)vocab.push_back(str(vf));kernel=e.phonon2_cpu_kernel_in_use();
 }
 ~Phonon(){if(dec)d.phonon2_tdt_destroy(dec);if(enc)e.phonon2_enc_destroy(enc);for(auto p:matrices)e.phonon2_cpu_destroy(p);}
 std::vector<float> mel(const std::vector<float>& wave){
  int N=int(wave.size()),T=1+N/160;std::vector<float>x(N+512),out(T*128);x[256]=wave[0];for(int i=1;i<N;i++)x[256+i]=wave[i]-.97f*wave[i-1];const float* window=tensors.at("window").f();const float* filters=tensors.at("mel_filters").f();
  for(int t=0;t<T;t++){
   std::array<std::complex<double>,512>a;for(int k=0;k<512;k++)a[k]=double(x[t*160+k]*window[k]);
   for(int i=1,j=0;i<512;i++){int bit=256;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j)std::swap(a[i],a[j]);}
   for(int len=2;len<=512;len*=2){std::complex<double>wlen=std::polar(1.0,-2*3.14159265358979323846/len);for(int i=0;i<512;i+=len){std::complex<double>w=1;for(int j=0;j<len/2;j++){auto u=a[i+j],v=a[i+j+len/2]*w;a[i+j]=u+v;a[i+j+len/2]=u-v;w*=wlen;}}}
   float power[257];for(int k=0;k<257;k++)power[k]=float(std::norm(a[k]));
   for(int j=0;j<128;j++){double val=0;for(int k=0;k<257;k++)val+=double(filters[j*257+k])*power[k];out[t*128+j]=std::log(float(val)+std::ldexp(1.0f,-24));}
  }
  for(int j=0;j<128;j++){double mean=0,var=0;for(int t=0;t<T;t++)mean+=out[t*128+j];mean/=T;for(int t=0;t<T;t++){double d=out[t*128+j]-mean;var+=d*d;}double den=std::sqrt(var/(T-1))+1e-5;for(int t=0;t<T;t++)out[t*128+j]=float((out[t*128+j]-mean)/den);}
  return out;
 }
 std::string transcribe(const std::vector<float>& wave,Timing& tm,const std::string& dump=""){
  auto t=Clock::now();auto features=mel(wave);tm.frontend=ms(t);if(!dump.empty()){std::ofstream f(dump,std::ios::binary);f.write(reinterpret_cast<const char*>(features.data()),features.size()*4);}
  int T=features.size()/128,T8=e.phonon2_enc_out_len(enc,T);std::vector<float>encoded(T8*1024),projected(T8*640);t=Clock::now();require(e.phonon2_enc_forward(enc,features.data(),T,encoded.data())==0,"Encoder forward failed");tm.encoder=ms(t);
  const float* w=tensors.at("encoder_projector.weight").f();const float* b=tensors.at("encoder_projector.bias").f();t=Clock::now();
  for(int i=0;i<T8;i++)for(int j=0;j<640;j++){float32x4_t a=vdupq_n_f32(0),c=vdupq_n_f32(0);for(int k=0;k<1024;k+=8){a=vfmaq_f32(a,vld1q_f32(encoded.data()+i*1024+k),vld1q_f32(w+j*1024+k));c=vfmaq_f32(c,vld1q_f32(encoded.data()+i*1024+k+4),vld1q_f32(w+j*1024+k+4));}projected[i*640+j]=vaddvq_f32(vaddq_f32(a,c))+b[j];}tm.projector=ms(t);
  std::vector<int32_t>ids(T8*12+64);t=Clock::now();int n=d.phonon2_tdt_decode_timed(dec,projected.data(),T8,ids.data(),nullptr,nullptr,ids.size());require(n>=0&&n<=int(ids.size()),"Decoder failed");tm.decoder=ms(t);std::string text;
  for(int i=0;i<n;i++){if(ids[i]<0||ids[i]>=int(vocab.size()))continue;auto p=vocab[ids[i]];if(p=="<unk>"||p=="<pad>"||(p.rfind("<|",0)==0&&p.size()>=4&&p.substr(p.size()-2)=="|>"))continue;text+=p;}
  size_t at;while((at=text.find("▁"))!=std::string::npos)text.replace(at,3," ");while(!text.empty()&&text.front()==' ')text.erase(0,1);while(!text.empty()&&text.back()==' ')text.pop_back();return text;
 }
};

#define MOON_NAMES(X) X(moonshine_load_transcriber_from_files) X(moonshine_free_transcriber) X(moonshine_create_stream) X(moonshine_start_stream) X(moonshine_stop_stream) X(moonshine_free_stream) X(moonshine_transcribe_add_audio_to_stream) X(moonshine_transcribe_stream)
struct Moonshine {
#define DECL(n) decltype(&::n) n;
 MOON_NAMES(DECL)
#undef DECL
 int model=-1;
 explicit Moonshine(const std::string& root,const std::string& lib,bool hints){
#ifdef FA_STATIC_MOONSHINE
#define SET(n) n=&::n;
#else
 auto handle=library(lib+"/moonshine");
#define SET(n) n=symbol<decltype(n)>(handle,#n);
#endif
 MOON_NAMES(SET)
#undef SET
 const char* terms="ONT,CBT,CSP,FTTP,fibre,fibre route,dBm,decibels,optical receive,optical receive reading,service test";
 moonshine_option_t opts[]={{"keyterms",hints?terms:""},{"keyterm_boost","2.0"},{"vad_threshold","0.5"},{"vad_window_duration","0.256"},{"transcription_interval","0.32"},{"max_tokens_per_second","12"},{"log_output_text","false"}};
 model=moonshine_load_transcriber_from_files((root+"/moonshine").c_str(),4,opts,7,30000);require(model>=0,"Moonshine model load failed");
 }
 ~Moonshine(){if(model>=0)moonshine_free_transcriber(model);}
 std::string transcribe(const std::vector<float>& wave,Timing& tm,bool paced){
  int stream=moonshine_create_stream(model,0);require(stream>=0,"Cannot create Moonshine stream");require(moonshine_start_stream(model,stream)==0,"Cannot start Moonshine stream");auto start=Clock::now();transcript_t* output=nullptr;
  for(size_t at=0;at<wave.size();at+=5120){auto n=std::min(size_t(5120),wave.size()-at);if(paced)std::this_thread::sleep_until(start+std::chrono::microseconds((at+n)*1000000/16000));require(moonshine_transcribe_add_audio_to_stream(model,stream,wave.data()+at,n,16000,0)==0,"Moonshine audio refused");require(moonshine_transcribe_stream(model,stream,0,&output)==0,"Moonshine stream failed");}
  auto t=Clock::now();require(moonshine_stop_stream(model,stream)==0,"Moonshine stop failed");require(moonshine_transcribe_stream(model,stream,1,&output)==0,"Moonshine finalization failed");tm.finalize=ms(t);std::string text;if(output)for(uint64_t i=0;i<output->line_count;i++)if(output->lines[i].text){if(!text.empty())text+=" ";text+=output->lines[i].text;}moonshine_free_stream(model,stream);return text;
 }
};

std::vector<float> pcm(const std::string& path){std::ifstream f(path,std::ios::binary|std::ios::ate);require(bool(f),"Audio missing: "+path);std::streamoff n=f.tellg();require(n>0&&n<=16000*2*65&&n%2==0,"Invalid audio length");f.seekg(0);std::vector<int16_t>b(size_t(n)/2);f.read(reinterpret_cast<char*>(b.data()),n);require(bool(f),"Truncated PCM");std::vector<float>a(b.size());for(size_t i=0;i<b.size();i++)a[i]=b[i]/32768.0f;return a;}

int main(int argc,char** argv){try{
 require(argc>=6,"usage: benchmark ROOT LIBDIR moonshine|phonon RUNS THREADS [FILTER] [paced]");std::string root=argv[1],lib=argv[2],name=argv[3],filter=argc>6?argv[6]:"";int runs=std::stoi(argv[4]),threads=std::stoi(argv[5]);require(runs>=1&&runs<=5&&threads>=1&&threads<=4,"Invalid benchmark limits");bool paced=argc>7&&std::string(argv[7])=="paced";bool hints=name.find("plain")==std::string::npos;bool isMoon=name.find("moonshine")==0;auto t=Clock::now();std::unique_ptr<Phonon>p;std::unique_ptr<Moonshine>m;if(isMoon)m=std::make_unique<Moonshine>(root,lib,hints);else p=std::make_unique<Phonon>(root,lib,threads,hints);double load=ms(t);
 std::cout<<"{\"event\":\"loaded\",\"model\":"<<quote(name)<<",\"loadMs\":"<<load<<",\"threads\":"<<(isMoon?0:threads)<<",\"kernel\":"<<(p?p->kernel:0)<<"}"<<std::endl;
 auto warm=pcm(root+"/audio/reading-fragment.pcm");Timing timing;if(p)p->transcribe(warm,timing);else m->transcribe(warm,timing,false);
 std::ifstream cases(root+"/cases.tsv");require(bool(cases),"Case list missing");std::vector<std::string>lines;std::string line;while(std::getline(cases,line))if(!line.empty())lines.push_back(line);
 for(int run=0;run<runs;run++)for(const auto& row:lines){std::istringstream s(row);std::string id,file,end;s>>id>>file>>end;if(!filter.empty()&&id.find(filter)==std::string::npos)continue;auto a=pcm(root+"/audio/"+file);double speechEnd=std::stod(end)/16000;
  // Paced runs use fixture-known endpoints to isolate recognizer scheduling
  // from VAD differences. They are not live microphone or full-bot latency.
  if(paced){double pause=id.rfind("s1-",0)==0?1.8:.45;size_t cut=std::min(a.size(),size_t((speechEnd+pause)*16000));a.resize(cut);}
  Timing tm;auto start=Clock::now();if(paced&&p)std::this_thread::sleep_for(std::chrono::microseconds(a.size()*1000000/16000));std::string text=p?p->transcribe(a,tm,filter=="s1-summary"&&run==0?root+"/features-native.f32":""):m->transcribe(a,tm,paced);double elapsed=ms(start);rusage usage{};getrusage(RUSAGE_SELF,&usage);
  std::cout<<std::setprecision(10)<<"{\"event\":\"result\",\"id\":"<<quote(id)<<",\"model\":"<<quote(name)<<",\"run\":"<<run<<",\"paced\":"<<(paced?"true":"false")<<",\"audioSeconds\":"<<a.size()/16000.0<<",\"wallMs\":"<<elapsed<<",\"frontendMs\":"<<tm.frontend<<",\"encoderMs\":"<<tm.encoder<<",\"projectorMs\":"<<tm.projector<<",\"decoderMs\":"<<tm.decoder<<",\"finalizeMs\":"<<tm.finalize<<",\"controlledReplyDelayMs\":"<<(paced?elapsed-speechEnd*1000:-1)<<",\"peakRssNativeUnits\":"<<usage.ru_maxrss<<",\"transcript\":"<<quote(text)<<"}"<<std::endl;
 }
 return 0;
 }catch(const std::exception& e){std::cerr<<"STT_BENCHMARK_ERROR: "<<e.what()<<std::endl;return 1;}}
