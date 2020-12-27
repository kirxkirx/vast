# The sole purpose of this file is to run gmake
# that will pick up the actual makefile called GNUmakefile
# If this file is running (after a user typed 'make') this 
# means GNU Make is not the default make system at this
# computer, so let's hope gmake is installed alongside the
# system make...

USEGNU=gmake $*
all:
	@$(USEGNU)
.DEFAULT:
	@$(USEGNU)

clean:
	gmake clean

objclean:
	gmake objclean

binclean:
	gmake binclean
		