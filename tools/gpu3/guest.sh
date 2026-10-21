echo "GPU3 guest start"
/gpu3/client /gpu3/libicd.so
echo "GPU3 rc=$?"
/gpu3/client /gpu3/libicd_missing.so
echo "GPU3 neg-missing rc=$?"
/gpu3/client /gpu3/libicd_partial.so
echo "GPU3 neg-partial rc=$?"
echo FX-END
