<?php

require_once __DIR__ . '/includes/bootstrap.php';
require_once __DIR__ . '/includes/config.php';
require_once __DIR__ . '/includes/autoload.php';

$handler = new RaspAP\Exceptions\ExceptionHandler;

require_once __DIR__ . '/includes/CSRF.php';
require_once __DIR__ . '/includes/session.php';
require_once __DIR__ . '/includes/defaults.php';
require_once __DIR__ . '/includes/locale.php';
require_once __DIR__ . '/includes/functions.php';

$clientIp = $_SERVER['REMOTE_ADDR'] ?? '';

if (!preg_match('/^10\.3\.141\.(?:[2-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-4])$/', $clientIp)) {
    http_response_code(403);
    exit('Guest Login Mode is available only from the PiBox Wi-Fi network.');
}


$message = '';
$auth = new \RaspAP\Auth\HTTPAuth;

if (!$auth->isLogged()) {
    $username = $_SERVER['PHP_AUTH_USER'] ?? '';
    $password = $_SERVER['PHP_AUTH_PW'] ?? '';

    if ($username === '' || $password === '' || !$auth->login($username, $password)) {
        header('WWW-Authenticate: Basic realm="PiBox Guest Login Mode"');
        http_response_code(401);
        exit('RaspAP administrator authentication required.');
    }
}
$messageType = 'info';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['portal_action'] ?? '';

    if ($action === 'enable') {
        $command = 'sudo -n /usr/local/sbin/pibox-portal on ' . escapeshellarg($clientIp) . ' 2>&1';
    } elseif ($action === 'disable') {
        $command = 'sudo -n /usr/local/sbin/pibox-portal off 2>&1';
    } else {
        $command = '';
    }

    if ($command !== '') {
        $output = [];
        $result = 1;
        exec($command, $output, $result);
        $message = implode("\n", $output);
        $messageType = ($result === 0) ? 'success' : 'danger';
    }
}

$stateFile = '/run/pibox-portal-client';
$active = is_readable($stateFile);
$activeClient = $active ? trim(file_get_contents($stateFile)) : '';
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <?= \RaspAP\Tokens\CSRF::metaTag(); ?>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>PiBox Guest Login Mode</title>
    <link href="/dist/bootstrap/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { background: #f4f6f8; }
        .portal-card { max-width: 680px; margin: 40px auto; }
        .status-dot {
            display: inline-block;
            width: 12px;
            height: 12px;
            margin-right: 8px;
            border-radius: 50%;
        }
        .status-on { background: #28a745; }
        .status-off { background: #dc3545; }
    </style>
</head>
<body>
<div class="container">
    <div class="card shadow portal-card">
        <div class="card-header bg-info text-white">
            <h4 class="mb-0">PiBox Guest Login Mode</h4>
        </div>

        <div class="card-body">
            <?php if ($message !== ''): ?>
                <div class="alert alert-<?= htmlspecialchars($messageType) ?>">
                    <?= nl2br(htmlspecialchars($message)) ?>
                </div>
            <?php endif; ?>

            <?php if ($active): ?>
                <div class="alert alert-success">
                    <span class="status-dot status-on"></span>
                    <strong>Guest Login Mode is active</strong><br>
                    Authorized device: <?= htmlspecialchars($activeClient) ?><br>
                    It will close automatically after 10 minutes.
                </div>

                <p>
                    Open the test page below. The workplace guest network should
                    redirect it to its login or terms-of-service page.
                </p>

                <a class="btn btn-primary btn-lg w-100 mb-3"
                   href="http://neverssl.com"
                   target="_blank"
                   rel="noopener">
                    Open Workplace Login Page
                </a>

                <form method="post">
                    <?= \RaspAP\Tokens\CSRF::hiddenField(); ?>
                    <input type="hidden" name="portal_action" value="disable">
                    <button type="submit" class="btn btn-danger w-100">
                        Close Guest Login Mode Now
                    </button>
                </form>
            <?php else: ?>
                <div class="alert alert-secondary">
                    <span class="status-dot status-off"></span>
                    <strong>Guest Login Mode is closed</strong>
                </div>

                <p>
                    This temporarily allows only this device
                    (<?= htmlspecialchars($clientIp) ?>) to reach the workplace
                    guest-network login page directly through wlan1.
                </p>

                <form method="post">
                    <?= \RaspAP\Tokens\CSRF::hiddenField(); ?>
                    <input type="hidden" name="portal_action" value="enable">
                    <button type="submit" class="btn btn-success btn-lg w-100">
                        Enable Guest Login Mode for 10 Minutes
                    </button>
                </form>
            <?php endif; ?>

            <a class="btn btn-outline-secondary w-100 mt-3" href="/">
                Return to RaspAP
            </a>
        </div>
    </div>
</div>
</body>
</html>
