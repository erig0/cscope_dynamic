NAME=cscope_dynamic
VERSION=0.7

SRC=	plugin/cscope_dynamic.vim

vimball: ${NAME}-${VERSION}.vmb.gz

${NAME}-${VERSION}.vmb: ${SRC}
	echo ${SRC} |tr ' ' '\n' > $@.list
	vim -c "let g:vimball_home='.'" -c "MkVimball! $@" -c "q!" $@.list
	rm $@.list

${NAME}-${VERSION}.vmb.gz: ${NAME}-${VERSION}.vmb
	gzip -c ${NAME}-${VERSION}.vmb > $@

clean:
	-rm ${NAME}-${VERSION}.vmb ${NAME}-${VERSION}.vmb.gz

.PHONY: vimball clean
