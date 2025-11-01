<?php
// === IRUL TUN JSON LIST TEMPLATES ===
// Path folder tempat file akun disimpan
$dir = __DIR__; // misalnya /var/www/html/

// Header agar bisa diakses lintas domain (CORS)
header('Access-Control-Allow-Origin: *');
header('Content-Type: application/json; charset=utf-8');

// Cek jika ada permintaan "file" untuk baca isi file
if (isset($_GET['file'])) {
    $file = basename($_GET['file']);
    $path = $dir . '/' . $file;
    if (!file_exists($path)) {
        http_response_code(404);
        echo json_encode(['error' => 'File tidak ditemukan']);
        exit;
    }
    echo json_encode([
        'file' => $file,
        'content' => file_get_contents($path)
    ]);
    exit;
}

// Jika tidak ada parameter, tampilkan semua file .txt
$files = glob($dir . '/*.txt');
$list = [];

foreach ($files as $f) {
    $name = basename($f);
    $parts = explode('-', $name, 2);
    $type = isset($parts[1]) ? strtolower($parts[0]) : '';
    $account = isset($parts[1]) ? basename($parts[1], '.txt') : '';
    $list[] = [
        'file' => $name,
        'type' => $type,
        'account' => $account,
        'size' => filesize($f),
        'modified' => date('Y-m-d H:i:s', filemtime($f))
    ];
}

echo json_encode([
    'server' => $_SERVER['HTTP_HOST'],
    'count' => count($list),
    'files' => $list
], JSON_PRETTY_PRINT);