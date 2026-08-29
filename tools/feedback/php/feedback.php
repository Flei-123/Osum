<?php
// Internes Feedback-Postfach fuer FleiTec-Apps. Nimmt POST (JSON) entgegen
// und haengt es als JSONL an eine Datei ausserhalb des Web-Roots an.
//
// RUNDE FEEDBACK (28.08.2026). Zwei Dinge kommen dazu und EINES bleibt:
//
//   NEU   ein optionales Feld `image` -- ein PNG (oder JPEG), als base64
//         oder als data:-URL. Hart begrenzt, nach MAGISCHEN OKTETTEN
//         geprueft und nicht nach der Endung, abgelegt AUSSERHALB des
//         Web-Roots unter einem Namen, den DIESER Server vergibt.
//   NEU   eine Begrenzung je Absender-Adresse und Zeitfenster.
//   BLEIBT der alte Vertrag, Oktett fuer Oktett: wer kein `image`
//         schickt, bekommt genau die Antwort von vorher --
//         {"ok":true,"id":"..."} -- und der Satz im JSONL hat dieselben
//         Felder in derselben Reihenfolge. FleiLauncher und FreeViewer
//         merken von dieser Runde nichts.
//
// WARUM DER NAME NICHT AUS DER ANFRAGE KOMMT. Das ist die klassische
// Luecke bei Upload-Endpunkten: ein Dateiname aus der Anfrage traegt
// `../` oder `.php` mit sich, und dann liegt fremder Code im Web-Root.
// Hier gibt es keinen Dateinamen aus der Anfrage. Der Name IST die
// zufaellige Satz-Kennung, die Endung kommt aus den magischen Oktetten,
// und das Verzeichnis liegt ohnehin dort, wo Apache nichts ausliefert.

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); echo json_encode(['ok'=>false,'error'=>'POST only']); exit; }

$DIR   = '/var/lib/fleifeedback';
$IMGD  = $DIR.'/bilder';
$RATED = $DIR.'/rate';

// ----------------------------------------------------- die Begrenzung
//
// Zwei Fenster, weil eines nicht reicht: das kurze haelt den Finger auf
// der Absendetaste auf, das lange den Eimer, der ueber Nacht ausgeleert
// wird. Gezaehlt wird je ADRESSE, und die Adresse steht nur als Streuwert
// in einem Dateinamen -- eine Liste der Absender entsteht dabei nicht.
const RATE_SHORT_WINDOW = 600;   // 10 Minuten
const RATE_SHORT_MAX    = 8;
const RATE_LONG_WINDOW  = 86400; // 24 Stunden
const RATE_LONG_MAX     = 60;
const IMG_MAX = 4194304;         // 4 MiB, entschluesselt

function client_ip() {
    // Hinter dem openresty-Frontproxy ist REMOTE_ADDR der Proxy. Der
    // Proxy setzt X-Forwarded-For; genommen wird der ERSTE Eintrag, und
    // nur wenn REMOTE_ADDR wirklich privat ist -- sonst koennte jeder
    // Absender sich seine eigene Zaehlung aussuchen.
    $ra = $_SERVER['REMOTE_ADDR'] ?? '';
    $xf = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? '';
    $public = filter_var($ra, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE|FILTER_FLAG_NO_RES_RANGE);
    if ($xf !== '' && $public === false) {
        $first = trim(explode(',', $xf)[0]);
        if (filter_var($first, FILTER_VALIDATE_IP)) return $first;
    }
    return $ra;
}

function rate_ok($dir, $ip, &$retry) {
    if ($ip === '') return true;
    if (!is_dir($dir)) @mkdir($dir, 0770, true);
    $f = $dir.'/'.hash('sha256', $ip).'.json';
    $now = time();
    $fp = @fopen($f, 'c+');
    if (!$fp) return true; // lieber annehmen als wegen der Zaehlung verlieren
    flock($fp, LOCK_EX);
    $raw = stream_get_contents($fp);
    $ts = json_decode($raw ?: '[]', true);
    if (!is_array($ts)) $ts = [];
    $keep = [];
    foreach ($ts as $t) { if (is_int($t) && $t > $now - RATE_LONG_WINDOW) $keep[] = $t; }
    $ts = $keep;
    $short = 0;
    foreach ($ts as $t) { if ($t > $now - RATE_SHORT_WINDOW) $short++; }
    $ok = true;
    if ($short >= RATE_SHORT_MAX)      { $ok = false; $retry = RATE_SHORT_WINDOW; }
    elseif (count($ts) >= RATE_LONG_MAX) { $ok = false; $retry = RATE_LONG_WINDOW; }
    if ($ok) {
        $ts[] = $now;
        ftruncate($fp, 0); rewind($fp); fwrite($fp, json_encode($ts));
    }
    flock($fp, LOCK_UN); fclose($fp);
    return $ok;
}

$raw = file_get_contents('php://input');
$in = json_decode($raw, true);
if (!is_array($in)) { $in = $_POST; }

function s($in,$k,$max,$def=''){ $v = isset($in[$k]) ? trim((string)$in[$k]) : $def; if (mb_strlen($v)>$max) $v = mb_substr($v,0,$max); return $v; }

$message = s($in,'message',6000);
if ($message === '') { http_response_code(400); echo json_encode(['ok'=>false,'error'=>'message required']); exit; }

$type = s($in,'type',20,'other');
if (!in_array($type, ['bug','feature','other'], true)) $type = 'other';

$ip = client_ip();
$retry = 0;
if (!rate_ok($RATED, $ip, $retry)) {
    http_response_code(429);
    header('Retry-After: '.$retry);
    echo json_encode(['ok'=>false,'error'=>'too many reports, try later']);
    exit;
}

$rec = [
  'id'      => bin2hex(random_bytes(6)),
  'ts'      => gmdate('c'),
  'project' => s($in,'project',60,'Unknown'),
  'type'    => $type,
  'message' => $message,
  'contact' => s($in,'contact',200),
  'version' => s($in,'version',40),
  'os'      => s($in,'os',300),
  'user'    => s($in,'user',80),
  'ip'      => $_SERVER['REMOTE_ADDR'] ?? '',
];

// ------------------------------------------------------------ das Bild
//
// DREI TORE, und ein Bild muss durch alle drei:
//   1. die GROESSE, gemessen an den entschluesselten Oktetten und nicht
//      an der base64-Zeichenkette;
//   2. die MAGISCHEN OKTETTE -- PNG faengt mit 89 50 4E 47 0D 0A 1A 0A
//      an, JPEG mit FF D8 FF. Die Endung sagt hier gar nichts, weil es
//      keine gibt: sie wird aus diesen Oktetten VERGEBEN;
//   3. `getimagesizefromstring`, das den Kopf wirklich liest. Etwas, das
//      die acht Oktette vorne traegt und dahinter kein Bild ist, faellt
//      hier durch.
// Ausgefuehrt wird nichts, geoeffnet wird nichts, verkleinert wird
// nichts -- die Oktette werden abgelegt und sonst nichts mit ihnen getan.

$imgerr = '';
$imgbytes = null;
$imgext = '';
$imgw = 0; $imgh = 0;

$b64 = '';
if (isset($in['image']) && is_string($in['image'])) {
    $b64 = trim($in['image']);
} elseif (!empty($_FILES['image']['tmp_name']) && is_uploaded_file($_FILES['image']['tmp_name'])) {
    if (($_FILES['image']['size'] ?? 0) <= IMG_MAX) {
        $imgbytes = @file_get_contents($_FILES['image']['tmp_name'], false, null, 0, IMG_MAX + 1);
    } else {
        $imgerr = 'image too large';
    }
}

if ($b64 !== '') {
    // data:-URL erlaubt, aber nur der Teil hinter dem Komma zaehlt.
    $p = strpos($b64, 'base64,');
    if ($p !== false) $b64 = substr($b64, $p + 7);
    $b64 = preg_replace('/\s+/', '', $b64);
    // 4 MiB roh sind hoechstens 5 592 408 base64-Zeichen. Vorher pruefen,
    // damit gar nicht erst entschluesselt wird, was ohnehin zu gross ist.
    if (strlen($b64) > (int)ceil(IMG_MAX / 3) * 4 + 16) {
        $imgerr = 'image too large';
    } else {
        $d = base64_decode($b64, true);
        if ($d === false)            $imgerr = 'image is not base64';
        elseif (strlen($d) > IMG_MAX) $imgerr = 'image too large';
        elseif (strlen($d) < 16)      $imgerr = 'image too small';
        else                          $imgbytes = $d;
    }
}

if ($imgbytes !== null && $imgerr === '') {
    if (substr($imgbytes, 0, 8) === "\x89PNG\r\n\x1a\n")      { $imgext = 'png'; }
    elseif (substr($imgbytes, 0, 3) === "\xFF\xD8\xFF")       { $imgext = 'jpg'; }
    else { $imgerr = 'not a PNG or JPEG'; }

    if ($imgerr === '') {
        $info = @getimagesizefromstring($imgbytes);
        $t = is_array($info) ? ($info[2] ?? 0) : 0;
        if (!is_array($info) || ($t !== IMAGETYPE_PNG && $t !== IMAGETYPE_JPEG)) {
            $imgerr = 'image header is not readable';
        } else {
            $imgw = (int)$info[0]; $imgh = (int)$info[1];
            if ($imgw < 1 || $imgh < 1 || $imgw > 20000 || $imgh > 20000) $imgerr = 'image dimensions out of range';
        }
    }

    if ($imgerr === '') {
        if (!is_dir($IMGD)) @mkdir($IMGD, 0770, true);
        // DER NAME KOMMT VON HIER. `$rec['id']` sind zwoelf Zeichen aus
        // `random_bytes`, die Endung aus den magischen Oktetten oben.
        // Nichts davon stand in der Anfrage.
        $fn = $rec['id'].'.'.$imgext;
        if (@file_put_contents($IMGD.'/'.$fn, $imgbytes) === strlen($imgbytes)) {
            @chmod($IMGD.'/'.$fn, 0640);
            $rec['image']       = $fn;
            $rec['image_bytes'] = strlen($imgbytes);
            $rec['image_w']     = $imgw;
            $rec['image_h']     = $imgh;
        } else {
            $imgerr = 'image could not be stored';
        }
    }
}
if ($imgerr !== '') $rec['image_error'] = $imgerr;

$fp = fopen($DIR.'/feedback.jsonl', 'ab');
if ($fp) { flock($fp, LOCK_EX); fwrite($fp, json_encode($rec, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES)."\n"); flock($fp, LOCK_UN); fclose($fp); }
else { http_response_code(500); echo json_encode(['ok'=>false,'error'=>'store failed']); exit; }

// DIE ANTWORT IST DIE ALTE. `image` und `image_error` kommen nur dazu,
// wenn ein Bild dabei war -- ein Absender von vorher sieht denselben
// Rumpf wie vorher.
$out = ['ok'=>true,'id'=>$rec['id']];
if (isset($rec['image'])) $out['image'] = true;
if ($imgerr !== '')       $out['image_error'] = $imgerr;
echo json_encode($out);
