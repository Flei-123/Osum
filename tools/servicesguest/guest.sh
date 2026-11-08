echo MARK-caps
svcproof caps
echo MARK-store
svcproof set proofapp greeting hello
svcproof has proofapp greeting
svcproof get proofapp greeting
svcproof set proofapp greeting second
svcproof get proofapp greeting
ls /data/proofapp/services
svcproof set proofbpp greeting foreign
svcproof get proofbpp greeting
svcproof get proofapp greeting
svcproof gen proofapp big 65536
svcproof sum proofapp big
svcproof gen proofapp toobig 65537
svcproof has proofapp toobig
svcproof set proofapp bad/key x
svcproof set .. key x
svcproof set proofapp .. x
svcproof get proofapp missing
svcproof rm proofapp greeting
svcproof has proofapp greeting
svcproof get proofapp greeting
svcproof rm proofapp greeting
svcproof rm proofapp big
ls /data/proofapp/services
echo MARK-clip
svcproof copy clipboardtext
svcproof paste
svcproof copy second-value
svcproof paste
echo MARK-end
