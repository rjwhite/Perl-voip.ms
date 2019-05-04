# If you run a install as root, it will install into a system directory
# Otherwise it will install into your HOME

SYS_MANPAGES	= /usr/local/man/man1
USER_MANPAGES	= ${HOME}/doc/man/man1
SYS_DEST_DIR	= /usr/local/bin
USER_DEST_DIR	= ${HOME}/bin
MODE			= 755

install:	${DEST_DIR}/voip

${DEST_DIR}/voip:
	@if [ `whoami` = 'root' ]; then \
		echo "I am Groot!" ; \
		echo "Installing scripts into ${SYS_DEST_DIR}" ; \
		if [ ! -d ${SYS_DEST_DIR} ]; then \
			mkdir -p ${SYS_DEST_DIR} ; \
		fi ;\
		install -p -m ${MODE} get-cdrs.plx ${SYS_DEST_DIR}/get-cdrs ;\
		install -p -m ${MODE} black-list.plx ${SYS_DEST_DIR}/black-list ;\
		install -p -m ${MODE} get-did-info.plx ${SYS_DEST_DIR}/get-did-info ;\
		install -p -m ${MODE} send-sms-message.plx ${SYS_DEST_DIR}/send-sms-message ;\
		install -p -m ${MODE} write-phone-CDR-records.sh ${SYS_DEST_DIR}/write-phone-CDR-records ;\
	else \
		echo "I am NOT Groot!" ; \
		echo "Installing scripts into ${USER_DEST_DIR}" ; \
		if [ ! -d ${USER_DEST_DIR} ]; then \
			mkdir -p ${USER_DEST_DIR} ; \
		fi ;\
		install -p -m ${MODE} get-cdrs.plx ${USER_DEST_DIR}/get-cdrs ;\
		install -p -m ${MODE} black-list.plx ${USER_DEST_DIR}/black-list ;\
		install -p -m ${MODE} get-did-info.plx ${USER_DEST_DIR}/get-did-info ;\
		install -p -m ${MODE} send-sms-message.plx ${USER_DEST_DIR}/send-sms-message ;\
		install -p -m ${MODE} write-phone-CDR-records.sh ${USER_DEST_DIR}/write-phone-CDR-records ;\
	fi

man:
	@if [ `whoami` = 'root' ]; then \
		echo "I am Groot!" ; \
		echo "Installing man-pages into ${SYS_MANPAGES}" ; \
		mkdir -p ${SYS_MANPAGES} ; \
		cp doc/man/man1/*.1 ${SYS_MANPAGES} ; \
	else \
		echo "I am NOT Groot!" ; \
		echo "Installing man-pages into ${USER_MANPAGES}" ; \
		mkdir -p ${USER_MANPAGES} ; \
		cp doc/man/man1/*.1 ${USER_MANPAGES} ; \
	fi
