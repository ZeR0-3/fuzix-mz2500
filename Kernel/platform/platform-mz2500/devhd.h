#ifndef __DEVHD_DOT_H__
#define __DEVHD_DOT_H__

int hd_open(uint_fast8_t minor, uint16_t flag);
int hd_read(uint_fast8_t minor, uint_fast8_t rawflag, uint_fast8_t flag);
int hd_write(uint_fast8_t minor, uint_fast8_t rawflag, uint_fast8_t flag);
void hd_probe(void);

#endif
