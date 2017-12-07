DEST_DIR	= ${HOME}/bin
MODE        = 755

install:	directories \
			${DEST_DIR}/voip

directories: 
	@if [ ! -d ${DEST_DIR} ]; then \
		mkdir -p ${DEST_DIR} ; \
	fi

${DEST_DIR}/voip:
	install -p -m ${MODE} get-cdrs.plx ${DEST_DIR}/get-cdrs
	install -p -m ${MODE} write-phone-CDR-records.sh ${DEST_DIR}/write-phone-CDR-records
