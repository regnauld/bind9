include $(top_srcdir)/Makefile.top
include $(top_srcdir)/Makefile.tests

AM_CPPFLAGS +=			\
	$(LIBISC_CFLAGS)	\
	$(LIBDNS_CFLAGS)	\
	$(LIBISCCFG_CFLAGS)

LDADD +=			\
	$(LIBISC_LIBS)		\
	$(LIBDNS_LIBS)		\
	$(LIBISCCFG_LIBS)

check_PROGRAMS =	\
	duration_test	\
	parser_test

TESTS = $(check_PROGRAMS)

unit-local: check

LOG_COMPILER = $(builddir)/../../unit-test-driver.sh
