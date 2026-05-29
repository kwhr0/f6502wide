#include <stdio.h>
#include <stdint.h>

#define N		0x800

static uint8_t m[0x10000];

static int getHex(char *&p, int n) {
	int r = 0;
	do {
		int c = *p++ - '0';
		if (c > 10) c -= 'A' - '0' - 10;
		if (c >= 0 && c < 16) r = r << 4 | c;
	} while (--n > 0);
	return r;
}

static void loadIntelHex(FILE *fi) {
	int ofs = 0;
	char s[256];
	while (fgets(s, sizeof(s), fi)) if (*s == ':') {
		char *p = s + 1;
		int n = getHex(p, 2), a = getHex(p, 4), t = getHex(p, 2);
		if (!t)
			while (--n >= 0) {
				if (ofs + a < 0x10000) m[ofs + a++] = getHex(p, 2);
			}
		else if (t == 2)
			ofs = getHex(p, 4) << 4;
//		else if (t == 4)
//			ofs = getHex(p, 4) << 16;
		else break;
	}
}

int main(int argc, char *argv[]) {
	if (argc != 2) return 1;
	FILE *fi = fopen(argv[1], "r");
	if (!fi) return 2;
	loadIntelHex(fi);
	fclose(fi);
	fi = fopen("ram.mem", "w");
	if (!fi) return 3;
	for (int i = 0; i < N; i++)
		fprintf(fi, "%02x\n", m[i] & 0xff);
	fclose(fi);
	return 0;
}
