#include <stdint.h>
int fa_available(void);
int fa_load(const unsigned char *data,uint64_t size);
const char *fa_last_error(void);
int fa_init(const char *system,const char *tools);
int fa_transcribe(const float *pcm,int samples,const char *language,char *out,int capacity);
int fa_complete(const char *text,char *out,int capacity);
void fa_reset(void);
