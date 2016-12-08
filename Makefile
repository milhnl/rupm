#rupm - Relocatable User Package Manager

include config.mk

SHSRC = $(wildcard *.sh) #Script sources
SHTGT = $(SRC:%.sh=${DESTDIR}${PREFIX}/bin/%) #Script targets
SRC = ${SHSRC}

dist:
	@echo creating dist tarball
	@mkdir -p ${NAME}-${VERSION}
	@cp -R ${SRC} config.mk Makefile ${NAME}-${VERSION}
	@tar -cf ${NAME}-${VERSION}.tar ${NAME}-${VERSION}
	@gzip ${NAME}-${VERSION}.tar
	@rm -rf ${NAME}-${VERSION}

${SHTGT}: ${SHSRC}
	@mkdir -p ${DESTDIR}${PREFIX}/bin
	@cp -f $(@F).sh $@
	@chmod 755 $@

install: ${SHTGT}

uninstall:
	@echo removing executable files from ${DESTDIR}${PREFIX}/bin
	@rm -f ${SHTGT}

.PHONY: dist install uninstall
