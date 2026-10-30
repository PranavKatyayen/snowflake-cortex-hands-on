# Turns an episode's medium.md into medium.html: open it in Chrome, click "Copy for Medium",
# paste into an empty Medium story. Code blocks stay whole, tables become lists (Medium has no
# tables) and relative images point at the public GitHub copy.
#
#   .\tools\medium-export.ps1 -Markdown episodes\01-mcp-server\medium.md
param(
    [Parameter(Mandatory = $true)][string]$Markdown,
    [string]$RawBase = "https://raw.githubusercontent.com/PranavKatyayen/snowflake-cortex-hands-on/main/"
)

$mdPath   = (Resolve-Path $Markdown).Path
$repoRoot = Split-Path -Parent $PSScriptRoot
$relDir   = (Split-Path -Parent $mdPath).Substring($repoRoot.Length).TrimStart('\').Replace('\', '/') + '/'
$b64      = [Convert]::ToBase64String([IO.File]::ReadAllBytes($mdPath))
$outPath  = [IO.Path]::ChangeExtension($mdPath, '.html')

$html = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Medium Export</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js"></script>
<style>
  :root { --bg:#fff; --fg:#242424; --muted:#6b6b6b; --code:#f2f2f2; --accent:#1a8917; --mark:#fff3b0; }
  body { margin:0; background:var(--bg); color:var(--fg); font:18px/1.6 Georgia, serif; }
  .bar { position:sticky; top:0; background:#fafafa; border-bottom:1px solid #e6e6e6; padding:12px 16px;
         font:14px/1.4 system-ui, sans-serif; display:flex; gap:12px; align-items:center; flex-wrap:wrap; }
  .bar button { background:var(--accent); color:#fff; border:0; border-radius:20px; padding:8px 18px; font-size:14px; cursor:pointer; }
  .bar span { color:var(--muted); }
  #post { max-width:720px; margin:32px auto; padding:0 16px; }
  #post pre { background:var(--code); padding:16px; overflow-x:auto; font:14px/1.5 Menlo, Consolas, monospace; }
  #post code { background:var(--code); font-family:Menlo, Consolas, monospace; font-size:0.85em; }
  #post img { max-width:100%; }
  #post .todo { background:var(--mark); }
</style>
</head>
<body>
<div class="bar">
  <button id="copy">Copy for Medium</button>
  <span id="status">Open a new Medium story, click Copy, then paste into the title line.</span>
</div>
<article id="post"></article>
<script>
const MD_B64 = "__B64__";
const IMG_BASE = "__IMGBASE__";

const bytes = Uint8Array.from(atob(MD_B64), c => c.charCodeAt(0));
const post = document.getElementById('post');
post.innerHTML = marked.parse(new TextDecoder().decode(bytes));

// Images: relative paths -> public GitHub copy, so Medium can fetch them on paste.
post.querySelectorAll('img').forEach(img => {
  const src = img.getAttribute('src');
  if (!/^https?:/.test(src)) img.src = IMG_BASE + src;
});

// Code: one <pre> with <br> lines. Blank lines become a non-breaking space,
// which stops Medium from splitting one block into several.
post.querySelectorAll('pre').forEach(pre => {
  const lines = pre.textContent.replace(/\n$/, '').split('\n');
  const fresh = document.createElement('pre');
  lines.forEach((line, i) => {
    if (i) fresh.appendChild(document.createElement('br'));
    fresh.appendChild(document.createTextNode(line.trim() === '' ? ' ' : line));
  });
  pre.replaceWith(fresh);
});

// Tables: Medium has none, so each row becomes a bullet.
post.querySelectorAll('table').forEach(table => {
  const heads = [...table.querySelectorAll('thead th')].map(th => th.textContent.trim());
  const ul = document.createElement('ul');
  table.querySelectorAll('tbody tr').forEach(tr => {
    const cells = [...tr.children];
    const li = document.createElement('li');
    const first = document.createElement('strong');
    first.innerHTML = cells[0].innerHTML;
    li.appendChild(first);
    if (cells.length === 2) {
      li.insertAdjacentHTML('beforeend', ' — ' + cells[1].innerHTML);
    } else {
      const rest = cells.slice(1).map((c, i) => (heads[i + 1] ? heads[i + 1] + ': ' : '') + c.innerHTML);
      li.insertAdjacentHTML('beforeend', ' — ' + rest.join(' · '));
    }
    ul.appendChild(li);
  });
  table.replaceWith(ul);
});

// Placeholders stay visible so nothing gets published by accident.
post.querySelectorAll('code').forEach(c => {
  if (/^\[(SCREENSHOT|TEASER|LINK)/.test(c.textContent)) c.classList.add('todo');
});

document.getElementById('copy').onclick = () => {
  const range = document.createRange();
  range.selectNodeContents(post);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
  const ok = document.execCommand('copy');
  sel.removeAllRanges();
  document.getElementById('status').textContent = ok
    ? 'Copied. Paste into an empty Medium story (Ctrl+V on the title line).'
    : 'Copy failed: press Ctrl+A, Ctrl+C on the article instead.';
};
</script>
</body>
</html>
'@

$html = $html.Replace('__B64__', $b64).Replace('__IMGBASE__', $RawBase + $relDir)
[IO.File]::WriteAllText($outPath, $html, (New-Object Text.UTF8Encoding $false))
Write-Host "Wrote $outPath"
