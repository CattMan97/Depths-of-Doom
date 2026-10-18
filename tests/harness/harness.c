/* Headless Atari XL test harness for Depths of Doom, on libatari800.

   usage: harness CART.CAR OUTPREFIX SCRIPT     (script mode)
          harness CART.CAR OUTPREFIX -          (interactive mode, on stdin)

   The machine: an XL with the built-in Altirra OS and BASIC, NTSC, 64K
   (RAM=16/64/128/320/... to change it).  Joystick port 1.

   Environment:
     RAM=n       memory in K (16 = a stock 600XL, 64 = 800XL, 128 = 130XE, 320)
     SEED=n      POKEY's random counter at power-on (stands in for a power-on)
     NOBASIC=1   no built-in BASIC
     RAMOUT=f    interactive mode: where to write the 64K RAM after each step
     WAV=f       record the sound to a WAV file
     AUDLOG=f    script mode: log AUDF1-4 and AUDC1-4 (8 bytes) every frame

   Input encoding (both modes): stick = the directions pressed, as a bit mask
   (1 up, 2 down, 4 left, 8 right; 0 = centred); trig 1 = fire pressed.

   Interactive mode, one command per line, each answered with "#DONE":
     FRAMES STICK TRIG [KEY]   run FRAMES frames with that input.  KEY is an
                               ATASCII character code held for those frames;
                               a negative KEY is a special key, pressed on the
                               first frame only (-2 = RESET, -3 = cold start).
                               Writes the RAM to $RAMOUT afterwards.
     P ADDR VALUE              poke RAM (decimal)
     S FILE                    screenshot (PPM, 336x240)
     W                         finish the WAV file now

   Script mode: SCRIPT is space-separated steps "FRAMES,STICK,TRIG[,FLAG,v...]".
   The flag acts before the frames run, except s, H and e, which act after:
     s                 screenshot to OUTPREFIX_NN.ppm
     K,code            hold key (ATASCII code) for the frames
     T / S / O         hold START / SELECT / OPTION
     m,hi,lo,val,n     fill n bytes from hi*256+lo with val
     p,x,xl,y,yl,al,ah player position and angle (zero page $82-$87)
     H                 start the 6502 profile: cycles per PC, written to
                       pchist.bin (65536 x uint32) at the end
   At the end it writes ram.bin and prints a status line. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "config.h"
#include "atari.h"
#include "memory.h"
#include "colours.h"
#include "screen.h"
#include "libatari800/libatari800.h"
#include "pokey.h"

extern unsigned int *CPU_pchist;        /* (atari800-pchist.patch) */
static unsigned int pch[65536];
static FILE *alog, *wav;
static long wavbytes;

static void shot(const char *fn) {
	unsigned char *s = libatari800_get_screen_ptr();
	FILE *f = fopen(fn, "wb");
	int x, y;
	fprintf(f, "P6\n336 240\n255\n");
	for (y = 0; y < 240; y++)
		for (x = 24; x < 360; x++) {
			int c = Colours_table[s[y * 384 + x]];
			fputc((c >> 16) & 255, f); fputc((c >> 8) & 255, f); fputc(c & 255, f);
		}
	fclose(f);
}

static void frame(input_template_t *in) {
	libatari800_next_frame(in);
	if (alog) { fwrite(POKEY_AUDF, 1, 4, alog); fwrite(POKEY_AUDC, 1, 4, alog); }
	if (wav) {
		int len = libatari800_get_sound_buffer_len();
		fwrite(libatari800_get_sound_buffer(), 1, len, wav); wavbytes += len;
	}
}

static void wavfin(void) {
	if (wav) {
		int ch = libatari800_get_num_sound_channels(), sr = libatari800_get_sound_frequency(), bs = libatari800_get_sound_sample_size();
		unsigned char h[44]; long v;
		memcpy(h, "RIFF", 4); v = 36 + wavbytes; h[4]=v; h[5]=v>>8; h[6]=v>>16; h[7]=v>>24;
		memcpy(h+8, "WAVEfmt ", 8); h[16]=16; h[17]=h[18]=h[19]=0; h[20]=1; h[21]=0; h[22]=ch; h[23]=0;
		h[24]=sr; h[25]=sr>>8; h[26]=sr>>16; h[27]=0; v = (long)sr*ch*bs; h[28]=v; h[29]=v>>8; h[30]=v>>16; h[31]=v>>24;
		h[32]=ch*bs; h[33]=0; h[34]=bs*8; h[35]=0; memcpy(h+36, "data", 4); v = wavbytes; h[40]=v; h[41]=v>>8; h[42]=v>>16; h[43]=v>>24;
		fseek(wav, 0, SEEK_SET); fwrite(h, 1, 44, wav); fclose(wav); wav = NULL;
	}
}

int main(int argc, char **argv) {
	char *args[] = {"atari800", "-xl", "-xl-rev", "altirra", "-basic", "-ntsc",
		"-cart", NULL, NULL};
	input_template_t in;
	UBYTE *m;
	int n = 0, i;
	char buf[512];
	if (argc != 4) { fprintf(stderr, "usage: harness CART.CAR OUTPREFIX SCRIPT|-\n"); return 2; }
	args[7] = argv[1];
	if (getenv("NOBASIC")) args[4] = "-nobasic";
	if (!libatari800_init(8, args)) { printf("init fail\n"); return 1; }
	MEMORY_ram_size = getenv("RAM") ? atoi(getenv("RAM")) : 64;
	Atari800_InitialiseMachine();
	alog = getenv("AUDLOG") ? fopen(getenv("AUDLOG"), "wb") : NULL;
	wav = getenv("WAV") ? fopen(getenv("WAV"), "wb") : NULL;
	if (wav) { int k; for (k = 0; k < 44; k++) fputc(0, wav); }
	POKEY_SetRandomCounter(getenv("SEED") ? atoi(getenv("SEED")) : 12345);
	libatari800_clear_input_array(&in);
	m = libatari800_get_main_memory_ptr();

	if (strcmp(argv[3], "-") == 0) {
		char line[600];
		const char *ro = getenv("RAMOUT");
		while (fgets(line, sizeof line, stdin)) {
			int fr, st, tr, kc = 0, a, v;
			if (line[0] == 'P') { if (sscanf(line + 1, "%d %d", &a, &v) == 2) m[a] = v; }
			else if (line[0] == 'S') { if (sscanf(line + 1, "%511s", buf) == 1) shot(buf); }
			else if (line[0] == 'W') wavfin();
			else {
				if (sscanf(line, "%d %d %d %d", &fr, &st, &tr, &kc) < 3) break;
				for (i = 0; i < fr; i++) {
					in.joy0 = st; in.trig0 = tr;
					if (kc < 0) { in.keychar = 0; in.special = (i == 0) ? -kc : 0; }
					else in.keychar = kc;
					frame(&in); n++;
				}
				in.keychar = 0; in.special = 0;
				if (alog) fflush(alog);
				if (ro) { FILE *f = fopen(ro, "wb"); fwrite(m, 1, 0x10000, f); fclose(f); }
			}
			printf("#DONE\n"); fflush(stdout);
		}
		wavfin();
		return 0;
	}

	{
		char *script = strdup(argv[3]);
		char *tok = strtok(script, " ");
		int shotno = 0;
		while (tok) {
			int frames = 0, stick = 0, trig = 0; char flag = 0;
			int v[6] = {0};
			sscanf(tok, "%d,%d,%d,%c,%d,%d,%d,%d,%d,%d", &frames, &stick, &trig, &flag, &v[0],&v[1],&v[2],&v[3],&v[4],&v[5]);
			if (flag == 'm') { int k; for (k = 0; k < v[3]; k++) m[((v[0] << 8) | v[1]) + k] = v[2]; }
			if (flag == 'p') { m[0x83]=v[0]; m[0x82]=v[1]; m[0x85]=v[2]; m[0x84]=v[3]; m[0x86]=v[4]; m[0x87]=v[5]; }
			in.select = (flag == 'S'); in.option = (flag == 'O'); in.start = (flag == 'T');
			in.keychar = (flag == 'K') ? v[0] : 0;
			for (i = 0; i < frames; i++) { in.joy0 = stick; in.trig0 = trig; frame(&in); n++; }
			if (flag == 'H') CPU_pchist = pch;
			if (flag == 's') { sprintf(buf, "%s_%02d.ppm", argv[2], shotno++); shot(buf); }
			tok = strtok(NULL, " ");
		}
	}
	if (CPU_pchist) { FILE *f = fopen("pchist.bin", "wb"); fwrite(pch, 4, 65536, f); fclose(f); }
	if (alog) fclose(alog);
	wavfin();
	printf("frames=%d fcount=%d rt=%d pa=%d px=%d.%d py=%d.%d ammo=%d\n", n,
		m[0x80], m[0x14], m[0x86] | (m[0x87] << 8), m[0x83], m[0x82], m[0x85], m[0x84], m[0x81]);
	{ FILE *f = fopen("ram.bin", "wb"); fwrite(m, 1, 65536, f); fclose(f); }
	return 0;
}
