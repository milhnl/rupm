#rupm - Relocatable User Package Manager
NAME = rupm
VERSION = 0.1
PREFIX ?= /usr/local

SHSRC = rupm.sh
SRC = ${SHSRC} bootstrap.sh

all:
	@echo "Only shell scripts, try 'make install' instead."

dist:
	@echo creating dist tarball
	@mkdir -p ${NAME}-${VERSION}
	@cp -R ${SRC} Makefile ${NAME}-${VERSION}
	@tar -cf ${NAME}-${VERSION}.tar ${NAME}-${VERSION}
	@gzip ${NAME}-${VERSION}.tar
	@rm -rf ${NAME}-${VERSION}

install: rupm.sh
	@cp -f rupm.sh "${DESTDIR}${PREFIX}/bin/rupm"
	@chmod 755 "${DESTDIR}${PREFIX}/bin/rupm"

uninstall:
	@rm -f "${DESTDIR}${PREFIX}/bin/rupm" \

.PHONY: dist install uninstall
