#include <stdint.h>
#include <stdlib.h>
#define API __attribute__((visibility("default")))
#ifdef __cplusplus
extern "C" {
#endif
#ifdef FIELD_VOICE_HAS_NEEDLE
#include "needle.h"
API int fa_available(void){ return 1; }
API int fa_load(const unsigned char *data,uint64_t size){setenv("NEEDLE_TELEMETRY","0",1);setenv("DO_NOT_TRACK","1",1);return needle_load(data,size);}
API const char *fa_last_error(void){return needle_last_error();}
API int fa_init(const char *system,const char *tools){return needle_init(system,tools,NULL);}
API int fa_transcribe(const float *pcm,int samples,const char *language,char *out,int capacity){return needle_transcribe(pcm,samples,language,NULL,0,out,capacity);}
API int fa_complete(const char *text,char *out,int capacity){return needle_complete(text,NULL,0,1024,out,capacity);}
API void fa_reset(void){needle_reset();}
#else
/* Explicit capability failure. No synthetic inference or cloud fallback. */
API int fa_available(void){return 0;}
API int fa_load(const unsigned char *data,uint64_t size){return -1;}
API const char *fa_last_error(void){return "NATIVE_LIBRARY_MISSING: provision models and rebuild for arm64";}
API int fa_init(const char *system,const char *tools){return -1;}
API int fa_transcribe(const float *pcm,int samples,const char *language,char *out,int capacity){return -1;}
API int fa_complete(const char *text,char *out,int capacity){return -1;}
API void fa_reset(void){}
#endif

#ifdef __cplusplus
}
#endif
