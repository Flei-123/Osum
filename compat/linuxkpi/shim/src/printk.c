#include "lkpi.h"

#define LINE_MAX 256

struct sink {
	char *buf;
	size_t size;
	size_t pos;
};

struct spec {
	bool left;
	bool zero;
	bool alt;
	int width;
	int precision;
	int wide;
};

static void put_char(struct sink *s, char c)
{
	if (s->pos + 1 < s->size)
		s->buf[s->pos] = c;
	s->pos++;
}

static void put_repeat(struct sink *s, char c, int count)
{
	while (count-- > 0)
		put_char(s, c);
}

static void put_number(struct sink *s, u64 value, bool negative, unsigned int base,
		       bool upper, const struct spec *sp)
{
	const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
	char tmp[24];
	int count = 0;
	int zeros;
	int length;
	int pad;
	int prefix = 0;
	bool zero_pad = sp->zero && !sp->left && sp->precision < 0;

	if (value == 0 && sp->precision != 0)
		tmp[count++] = '0';
	while (value) {
		tmp[count++] = digits[value % base];
		value /= base;
	}
	if (sp->alt && base == 16 && count)
		prefix = 2;
	zeros = sp->precision > count ? sp->precision - count : 0;
	length = count + zeros + prefix + (negative ? 1 : 0);
	pad = sp->width > length ? sp->width - length : 0;
	if (!sp->left && !zero_pad)
		put_repeat(s, ' ', pad);
	if (negative)
		put_char(s, '-');
	if (prefix) {
		put_char(s, '0');
		put_char(s, upper ? 'X' : 'x');
	}
	if (zero_pad)
		put_repeat(s, '0', pad);
	put_repeat(s, '0', zeros);
	while (count)
		put_char(s, tmp[--count]);
	if (sp->left)
		put_repeat(s, ' ', pad);
}

static void put_string(struct sink *s, const char *text, const struct spec *sp)
{
	int length = 0;
	int pad;
	int i;

	if (!text)
		text = "(null)";
	while (text[length] && (sp->precision < 0 || length < sp->precision))
		length++;
	pad = sp->width > length ? sp->width - length : 0;
	if (!sp->left)
		put_repeat(s, ' ', pad);
	for (i = 0; i < length; i++)
		put_char(s, text[i]);
	if (sp->left)
		put_repeat(s, ' ', pad);
}

static int parse_number(const char **fmt)
{
	int value = 0;

	while (**fmt >= '0' && **fmt <= '9') {
		value = value * 10 + (**fmt - '0');
		(*fmt)++;
	}
	return value;
}

static void put_integer(struct sink *s, va_list *args, char conv, const struct spec *sp)
{
	if (conv == 'd' || conv == 'i') {
		s64 value = sp->wide ? va_arg(*args, long long) : va_arg(*args, int);
		bool negative = value < 0;

		put_number(s, negative ? -(u64)value : (u64)value, negative, 10, false, sp);
		return;
	}
	{
		u64 value = sp->wide ? va_arg(*args, unsigned long long) :
				       va_arg(*args, unsigned int);
		unsigned int base = conv == 'o' ? 8 : (conv == 'u' ? 10 : 16);

		put_number(s, value, false, base, conv == 'X', sp);
	}
}

int vsnprintf(char *buf, size_t size, const char *fmt, va_list args)
{
	struct sink s = { buf, size, 0 };
	va_list ap;

	va_copy(ap, args);
	for (; *fmt; fmt++) {
		struct spec sp = { false, false, false, 0, -1, 0 };
		char conv;

		if (*fmt != '%') {
			put_char(&s, *fmt);
			continue;
		}
		fmt++;
		for (;; fmt++) {
			if (*fmt == '-')
				sp.left = true;
			else if (*fmt == '0')
				sp.zero = true;
			else if (*fmt == '#')
				sp.alt = true;
			else if (*fmt != '+' && *fmt != ' ')
				break;
		}
		if (*fmt == '*') {
			sp.width = va_arg(ap, int);
			if (sp.width < 0) {
				sp.left = true;
				sp.width = -sp.width;
			}
			fmt++;
		} else {
			sp.width = parse_number(&fmt);
		}
		if (*fmt == '.') {
			fmt++;
			if (*fmt == '*') {
				sp.precision = va_arg(ap, int);
				fmt++;
			} else {
				sp.precision = parse_number(&fmt);
			}
		}
		while (*fmt == 'l' || *fmt == 'z' || *fmt == 't' || *fmt == 'j' || *fmt == 'h') {
			if (*fmt != 'h')
				sp.wide++;
			fmt++;
		}
		conv = *fmt;
		if (!conv)
			break;
		switch (conv) {
		case 'd':
		case 'i':
		case 'u':
		case 'x':
		case 'X':
		case 'o':
			put_integer(&s, &ap, conv, &sp);
			break;
		case 'p':
			sp.alt = true;
			put_number(&s, (u64)va_arg(ap, void *), false, 16, false, &sp);
			break;
		case 'c':
			put_char(&s, (char)va_arg(ap, int));
			break;
		case 's':
			put_string(&s, va_arg(ap, const char *), &sp);
			break;
		case '%':
			put_char(&s, '%');
			break;
		default:
			put_char(&s, '%');
			put_char(&s, conv);
			break;
		}
	}
	va_end(ap);
	if (size)
		buf[s.pos < size ? s.pos : size - 1] = 0;
	return (int)s.pos;
}

int snprintf(char *buf, size_t size, const char *fmt, ...)
{
	va_list args;
	int length;

	va_start(args, fmt);
	length = vsnprintf(buf, size, fmt, args);
	va_end(args);
	return length;
}

int _printk(const char *fmt, ...)
{
	static char line[LINE_MAX];
	va_list args;
	int length;

	va_start(args, fmt);
	length = vsnprintf(line, sizeof(line), fmt, args);
	va_end(args);
	k_puts(line);
	return length;
}

void lkpi_halt(const char *file, int line)
{
	_printk("lkpi: BUG %s:%d\n", file, line);
	for (;;)
		__asm__ volatile("cli; hlt");
}
