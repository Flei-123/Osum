<?php
// Token-geschuetztes Feedback-Dashboard, nach Projekt gruppiert.
//
// RUNDE FEEDBACK (28.08.2026): DAS BILD. Ein Bildschirmfoto liegt
// AUSSERHALB des Web-Roots -- Apache kann es gar nicht ausliefern, und
// das ist der Sinn. Ausgeliefert wird es von HIER, und nur nachdem
// derselbe Token geprueft wurde, der auch die Liste freigibt:
//
//     feedback-dash.php?key=<token>&img=<id>.<png|jpg>
//
// `<id>` ist die zwoelfstellige Satzkennung und sonst nichts. Der Name
// wird gegen `^[0-9a-f]{12}\.(png|jpg)$` gehalten, BEVOR er an das
// Dateisystem geht -- kein Pfad, kein `..`, kein Punkt zu viel. Was
// nicht auf diese Form passt, wird nicht gesucht.
$DIR   = '/var/lib/fleifeedback';
$IMGD  = $DIR.'/bilder';
$TOKEN = trim(@file_get_contents($DIR.'/token.txt'));
$key = $_GET['key'] ?? '';
if (!$TOKEN || !hash_equals($TOKEN, (string)$key)) { http_response_code(403); header('Content-Type:text/plain'); echo 'Forbidden'; exit; }

// ------------------------------------------------------- das Bild raus
if (isset($_GET['img'])) {
    $n = (string)$_GET['img'];
    if (!preg_match('/^[0-9a-f]{12}\.(png|jpg)$/', $n)) { http_response_code(400); header('Content-Type:text/plain'); echo 'bad name'; exit; }
    $p = $IMGD.'/'.$n;
    if (!is_file($p)) { http_response_code(404); header('Content-Type:text/plain'); echo 'not found'; exit; }
    // Die Art kommt aus den MAGISCHEN OKTETTEN der Datei und nicht aus
    // ihrem Namen -- dieselbe Regel wie beim Annehmen.
    $head = @file_get_contents($p, false, null, 0, 8);
    if ($head === "\x89PNG\r\n\x1a\n")           $ct = 'image/png';
    elseif (substr($head,0,3) === "\xFF\xD8\xFF") $ct = 'image/jpeg';
    else { http_response_code(415); header('Content-Type:text/plain'); echo 'unsupported'; exit; }
    header('Content-Type: '.$ct);
    header('Content-Length: '.filesize($p));
    header('X-Content-Type-Options: nosniff');
    header('Content-Disposition: inline; filename="'.$n.'"');
    header('Cache-Control: private, max-age=300');
    readfile($p);
    exit;
}

$resPath = $DIR.'/resolved.json';
$resolved = json_decode(@file_get_contents($resPath) ?: '[]', true); if (!is_array($resolved)) $resolved = [];

// Aktion: erledigt togglen / loeschen
$action = $_GET['action'] ?? ''; $id = $_GET['id'] ?? '';
if ($action === 'toggle' && $id) {
  if (in_array($id,$resolved,true)) $resolved = array_values(array_diff($resolved,[$id])); else $resolved[] = $id;
  file_put_contents($resPath, json_encode(array_values($resolved)));
  header('Location: feedback-dash.php?key='.urlencode($key)); exit;
}
if ($action === 'delete' && $id) {
  $lines = file($DIR.'/feedback.jsonl', FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES) ?: [];
  $out = [];
  foreach ($lines as $ln){
    $r=json_decode($ln,true);
    if(is_array($r) && ($r['id']??'')===$id){
      // Das Bild geht mit. Sonst bliebe es fuer immer liegen -- und
      // ein geloeschter Satz mit einem Bildschirmfoto daneben ist
      // kein geloeschter Satz.
      $img = (string)($r['image'] ?? '');
      if ($img !== '' && preg_match('/^[0-9a-f]{12}\.(png|jpg)$/', $img)) @unlink($IMGD.'/'.$img);
      continue;
    }
    $out[]=$ln;
  }
  file_put_contents($DIR.'/feedback.jsonl', $out ? implode("\n",$out)."\n" : '');
  $resolved = array_values(array_diff($resolved,[$id])); file_put_contents($resPath, json_encode($resolved));
  header('Location: feedback-dash.php?key='.urlencode($key)); exit;
}

$lines = file($DIR.'/feedback.jsonl', FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES) ?: [];
$items = [];
foreach ($lines as $ln){ $r=json_decode($ln,true); if(is_array($r)) $items[]=$r; }
usort($items, fn($a,$b)=> strcmp($b['ts']??'', $a['ts']??''));

$byProject = [];
foreach ($items as $it){ $p=$it['project']?:'Unknown'; $byProject[$p][]=$it; }
ksort($byProject);
$openCount = count(array_filter($items, fn($x)=> !in_array($x['id']??'',$resolved,true)));
$shotCount = count(array_filter($items, fn($x)=> !empty($x['image'])));
function e($s){ return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }
function kb($n){ $n=(int)$n; return $n >= 1048576 ? round($n/1048576,1).' MiB' : round($n/1024).' KiB'; }
$k = e($key);
?>
<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>FleiTec Feedback</title>
<style>
:root{--bg:#07090f;--card:#0e1220;--card2:#151b2c;--line:rgba(255,255,255,.09);--txt:#e7ecf5;--mut:#8b93a7;--green:#1bd96a;--blue:#2b78ff;--amber:#f59e0b;}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--txt);font:14px/1.5 system-ui,Segoe UI,Roboto,sans-serif;padding:24px;max-width:960px;margin:0 auto}
h1{font-size:22px;margin:0 0 4px}.sub{color:var(--mut);margin:0 0 22px}
.proj{margin:22px 0 10px;font-size:16px;font-weight:700;display:flex;align-items:center;gap:10px}
.proj .n{background:var(--card2);color:var(--mut);font-size:12px;padding:2px 9px;border-radius:20px;font-weight:600}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin-bottom:10px}
.card.done{opacity:.5}
.row{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:8px}
.badge{font-size:11px;font-weight:700;padding:2px 9px;border-radius:6px;text-transform:uppercase;letter-spacing:.3px}
.bug{background:rgba(239,68,68,.15);color:#ff6b6b}.feature{background:rgba(43,120,255,.15);color:#6ea8ff}.other{background:rgba(139,147,167,.15);color:var(--mut)}
.shot{background:rgba(27,217,106,.13);color:var(--green)}
.warn{background:rgba(245,158,11,.15);color:var(--amber)}
.msg{white-space:pre-wrap;margin:6px 0 10px}
.meta{color:var(--mut);font-size:12px;display:flex;gap:14px;flex-wrap:wrap}
.act{margin-left:auto;display:flex;gap:8px}
a.btn{color:var(--txt);text-decoration:none;background:var(--card2);border:1px solid var(--line);padding:5px 11px;border-radius:7px;font-size:12px}
a.btn:hover{border-color:var(--green)}
a.del:hover{border-color:#ff6b6b;color:#ff6b6b}
.empty{color:var(--mut);text-align:center;padding:60px 0}
.ts{font-variant-numeric:tabular-nums}
/* RUNDE FEEDBACK: die Vorschau. Klein in der Karte, gross im Overlay. */
.thumbwrap{margin:2px 0 10px}
img.thumb{max-width:320px;max-height:180px;border:1px solid var(--line);border-radius:8px;display:block;cursor:zoom-in;background:#000}
.thumbcap{color:var(--mut);font-size:11px;margin-top:4px}
#lb{position:fixed;inset:0;background:rgba(0,0,0,.92);display:none;align-items:center;justify-content:center;z-index:50;cursor:zoom-out;padding:20px}
#lb.on{display:flex}
#lb img{max-width:100%;max-height:100%;border-radius:6px}
</style></head><body>
<h1>FleiTec Feedback</h1>
<p class="sub"><?=count($items)?> Meldungen · <?=$openCount?> offen · <?=$shotCount?> mit Bildschirmfoto</p>
<?php if(!$items): ?><div class="empty">Noch kein Feedback eingegangen.</div><?php endif; ?>
<?php foreach($byProject as $proj=>$list): ?>
  <div class="proj"><?=e($proj)?> <span class="n"><?=count($list)?></span></div>
  <?php foreach($list as $it): $done=in_array($it['id']??'',$resolved,true); $ty=$it['type']??'other'; $img=(string)($it['image']??''); ?>
    <div class="card <?=$done?'done':''?>">
      <div class="row">
        <span class="badge <?=e($ty)?>"><?=$ty==='bug'?'🐞 Bug':($ty==='feature'?'💡 Feature':'Sonstiges')?></span>
        <?php if($img): ?><span class="badge shot">🖼 Bild</span><?php endif; ?>
        <?php if(!empty($it['image_error'])): ?><span class="badge warn" title="<?=e($it['image_error'])?>">Bild abgelehnt</span><?php endif; ?>
        <?php if($done): ?><span class="badge other">✓ erledigt</span><?php endif; ?>
        <span class="ts meta"><?=e(str_replace(['T','+00:00'],[' ',' UTC'],$it['ts']??''))?></span>
        <span class="act">
          <a class="btn" href="?key=<?=$k?>&action=toggle&id=<?=e($it['id'])?>"><?=$done?'wieder öffnen':'erledigt'?></a>
          <a class="btn del" href="?key=<?=$k?>&action=delete&id=<?=e($it['id'])?>" onclick="return confirm('Wirklich löschen?')">löschen</a>
        </span>
      </div>
      <div class="msg"><?=e($it['message']??'')?></div>
      <?php if($img && preg_match('/^[0-9a-f]{12}\.(png|jpg)$/',$img)): ?>
      <div class="thumbwrap">
        <img class="thumb" loading="lazy" src="?key=<?=$k?>&img=<?=e($img)?>" alt="Bildschirmfoto" onclick="gross(this.src)">
        <div class="thumbcap"><?=e($it['image_w']??'?')?>×<?=e($it['image_h']??'?')?> · <?=kb($it['image_bytes']??0)?> · klicken für groß</div>
      </div>
      <?php endif; ?>
      <div class="meta">
        <?php if(!empty($it['version'])): ?><span>v<?=e($it['version'])?></span><?php endif; ?>
        <?php if(!empty($it['user'])): ?><span>👤 <?=e($it['user'])?></span><?php endif; ?>
        <?php if(!empty($it['contact'])): ?><span>✉ <?=e($it['contact'])?></span><?php endif; ?>
        <?php if(!empty($it['os'])): ?><span title="<?=e($it['os'])?>">OS: <?=e(mb_substr($it['os'],0,48))?></span><?php endif; ?>
        <?php if(!empty($it['ip'])): ?><span><?=e($it['ip'])?></span><?php endif; ?>
      </div>
    </div>
  <?php endforeach; ?>
<?php endforeach; ?>
<div id="lb" onclick="this.classList.remove('on')"><img id="lbi" alt=""></div>
<script>
function gross(src){ document.getElementById('lbi').src = src; document.getElementById('lb').classList.add('on'); }
document.addEventListener('keydown', function(e){ if(e.key==='Escape') document.getElementById('lb').classList.remove('on'); });
</script>
</body></html>
