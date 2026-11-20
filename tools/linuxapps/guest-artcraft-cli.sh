echo "AC start"
export HOME=/root TMPDIR=/tmp XDG_RUNTIME_DIR=/tmp RUST_BACKTRACE=1
mkdir -p /root /tmp/ac
cd /tmp/ac
run() {
    name=$1
    shift
    echo "AC $name begin"
    timeout ${AC_TMO:-300} "$@"
    echo "AC $name rc=$?"
}
echo "AC loader: $(ls -la /lib64/ld-linux-x86-64.so.2)"
run grid-version /opt/ac/gridcraft-cli --version
run grid-eval /opt/ac/gridcraft-cli eval '=SUM(1,2,3)*2'
run grid-run /opt/ac/gridcraft-cli run --sample budget --cmd 'home.bold={"range":"B4:F4"}' --out /tmp/ac/budget.xlsx
run grid-cat /opt/ac/gridcraft-cli cat /tmp/ac/budget.xlsx --range B4:F6
echo "AC budget size: $(ls -la /tmp/ac/budget.xlsx)"
run word-version /opt/ac/wordcraft-cli --version
echo "Hello ArtCraft" > /tmp/ac/in.txt
run word-convert /opt/ac/wordcraft-cli convert /tmp/ac/in.txt /tmp/ac/out.docx
run word-text /opt/ac/wordcraft-cli text /tmp/ac/out.docx
run word-pdf /opt/ac/wordcraft-cli convert /tmp/ac/out.docx /tmp/ac/out.pdf
echo "AC pdf size: $(ls -la /tmp/ac/out.pdf)"
run deck-version /opt/ac/deckcraft-cli --version
run deck-run /opt/ac/deckcraft-cli run --sample --cmd 'slide.new={"layout":"titleOnly","title":"Hello"}' --save /tmp/ac/hello.deckcraft
echo "AC deck size: $(ls -la /tmp/ac/hello.deckcraft)"
echo FX-END
