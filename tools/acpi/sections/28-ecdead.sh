ECASL=tools/ecquery/asl/ec
[ -f $ECASL.aml ] || iasl -p $ECASL $ECASL.asl > /dev/null 2>&1
qrun "$K" ecdead "osum acpiev evself evwait noring3 nofs" -acpitable "file=$ECASL.aml"
last=$(lastline ecdead '^acpiev: ready=')
chk_ge "EC declared but absent: the pump keeps running (runs in 9 s)" 200 "$(val "$last" pumpn)"
chk "EC declared but absent: kernel finished" 21 "$(cat "$D/ecdead.rc")"
chk_le "EC declared but absent: timeouts are bounded" 4 "$(val "$(line ecdead '^ec found=')" err)"
if [ -n "$KB" ]; then
    qrun "$KB" ecdeadbase "osum acpiev evself evwait noring3 nofs" -acpitable "file=$ECASL.aml"
    echo "  note  before: pump ran $(val "$(lastline ecdeadbase '^acpiev: ready=')" pumpn) times in 9 s"
fi
