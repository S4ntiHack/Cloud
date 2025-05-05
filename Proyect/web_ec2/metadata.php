<?php
header('Content-Type: application/json');

function get_metadata($path) {
    try {
        // Obtener token IMDSv2
        $token_url = 'http://169.254.169.254/latest/api/token';
        $token_context = stream_context_create([
            'http' => [
                'method' => 'PUT',
                'header' => "X-aws-ec2-metadata-token-ttl-seconds: 21600\r\n",
                'timeout' => 1
            ]
        ]);
        
        $token = @file_get_contents($token_url, false, $token_context);
        if ($token === false) return null;
        
        // Consultar metadatos con el token
        $url = 'http://169.254.169.254/latest/meta-data/' . $path;
        $context = stream_context_create([
            'http' => [
                'header' => "X-aws-ec2-metadata-token: $token\r\n",
                'timeout' => 1
            ]
        ]);
        
        $response = @file_get_contents($url, false, $context);
        return $response !== false ? trim($response) : null;
        
    } catch (Exception $e) {
        error_log('Error getting metadata: ' . $e->getMessage());
        return null;
    }
}

// Obtener todos los metadatos
$metadata = [
    'instanceId' => get_metadata('instance-id'),
    'publicIp' => get_metadata('public-ipv4'),
    'az' => get_metadata('placement/availability-zone'),
    'instanceType' => get_metadata('instance-type'),
    'isAWS' => get_metadata('instance-id') !== null
];

// Limpiar valores nulos
foreach ($metadata as $key => $value) {
    if ($value === null) {
        $metadata[$key] = 'No disponible';
    }
}

// Respuesta en formato JSON
echo json_encode($metadata, JSON_UNESCAPED_SLASHES);
?>
