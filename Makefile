#rupm - Relocatable User Package Manager
NAME = rupm
VERSION = 0.1
PREFIX ?= /usr/local

SHSRC = rupm.sh tarxenv.sh
SRC = ${SHSRC}

all:
	@echo "Only shell scripts, try 'make install' instead."

dist:
	@echo creating dist tarball
	@mkdir -p ${NAME}-${VERSION}
	@cp -R ${SRC} Makefile ${NAME}-${VERSION}
	@tar -cf ${NAME}-${VERSION}.tar ${NAME}-${VERSION}
	@gzip ${NAME}-${VERSION}.tar
	@rm -rf ${NAME}-${VERSION}

install: ${SHSRC}
	@for f in ${SHSRC}; do \
		cp -f $$f "${DESTDIR}${PREFIX}/bin/$${f%.*}"; \
		chmod 755 "${DESTDIR}${PREFIX}/bin/$${f%.*}"; \
	done

uninstall:
	@for $$f in ${SHSRC}; do \
		rm -f "${DESTDIR}${PREFIX}/bin/$${f%.*}" \
	done

.PHONY: dist install uninstall
