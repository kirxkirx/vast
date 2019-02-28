# Basic astronomical functions library - Win32 .DLL version

all:  astcheck.exe astephem.exe persian.exe jd.exe relativi.exe  \
      riseset3.exe get_test.exe ssattest.exe lunar.lib

lunar.lib: mini_dll.obj \
      alt_az.obj astfuncs.obj big_vsop.obj classel.obj com_file.obj \
      cospar.obj date.obj de_plan.obj delta_t.obj dist_pa.obj elp82dat.obj \
      getplane.obj get_time.obj jsats.obj lunar2.obj  \
      miscell.obj nutation.obj obliquit.obj pluto.obj precess.obj  \
      refract.obj refract4.obj rocks.obj showelem.obj \
      ssats.obj triton.obj vislimit.obj vsopson.obj
   del lunar.lib
   del lunar.dll
   link /DLL /MAP /IMPLIB:lunar.lib /DEF:lunar.def mini_dll.obj \
      alt_az.obj astfuncs.obj big_vsop.obj classel.obj com_file.obj \
      cospar.obj date.obj de_plan.obj delta_t.obj dist_pa.obj elp82dat.obj \
      getplane.obj get_time.obj jsats.obj lunar2.obj  \
      miscell.obj nutation.obj obliquit.obj pluto.obj precess.obj  \
      refract.obj refract4.obj rocks.obj showelem.obj \
      ssats.obj triton.obj vislimit.obj vsopson.obj >> err

jd.exe:  jd.obj lunar.lib
   link jd.obj lunar.lib

relativi.exe:  relativi.obj lunar.lib
   link relativi.obj lunar.lib

ssattest.exe:  ssattest.obj lunar.lib
   link ssattest.obj lunar.lib

astephem.exe:  astephem.obj eart2000.obj mpcorb.obj lunar.lib
   link astephem.obj eart2000.obj mpcorb.obj lunar.lib

astcheck.exe:  astcheck.obj eart2000.obj mpcorb.obj lunar.lib
   link astcheck.obj eart2000.obj mpcorb.obj lunar.lib

riseset3.exe: riseset3.obj lunar.lib
   link riseset3.obj lunar.lib

persian.exe: persian.obj solseqn.obj lunar.lib
   link persian.obj solseqn.obj lunar.lib

get_test.exe: get_test.obj lunar.lib
   link get_test.obj lunar.lib


CFLAGS=-W3 -Ox -GX -c -LD -DNDEBUG -nologo

.cpp.obj:
   cl $(CFLAGS) $< >> err
   type err

relativi.obj:
   cl /c /Od /W3 /DTEST_CODE relativi.cpp

riseset3.obj:
   cl /c /Od /W3 /DTEST_MAIN riseset3.cpp

ssats.obj: ssats.cpp
   cl -W3 -Od -GX -c -LD -I\myincl ssats.cpp >> err
   type err

