all: jd riseset3 astcheck astephem get_test


#CC=`../../lib/find_cpp_compiler.sh`
CC:=$(shell ../../lib/find_cpp_compiler.sh)
#CC != ../../lib/find_cpp_compiler.sh


#CFLAGS=-c -Wall -Wno-parentheses
CFLAGS=-c -w -Wno-parentheses

OBJS= alt_az.o astfuncs.o classel.o cospar.o date.o delta_t.o \
	de_plan.o dist_pa.o eart2000.o elp82dat.o getplane.o get_time.o \
	jsats.o lunar2.o miscell.o nutation.o obliquit.o precess.o \
	showelem.o ssats.o triton.o vsopson.o

lunar.a: $(OBJS)
	rm -f lunar.a
	ar rv lunar.a $(OBJS)

get_test: get_test.o lunar.a
	$(CC) -o get_test get_test.o lunar.a -lstdc++

jd: jd.o lunar.a
	$(CC) -o jd jd.o lunar.a -lstdc++

riseset3.o: riseset3.cpp
	$(CC) $(CFLAGS) -DTEST_MAIN riseset3.cpp

riseset3: riseset3.o lunar.a
	$(CC) -o riseset3 riseset3.o lunar.a -lstdc++

astephem:  astephem.o mpcorb.o lunar.a
	$(CC) -o astephem astephem.o mpcorb.o lunar.a -lstdc++

astcheck:  astcheck.o mpcorb.o lunar.a
	$(CC) -o astcheck astcheck.o mpcorb.o lunar.a -lstdc++

.cpp.o:
	$(CC) $(CFLAGS) $<
