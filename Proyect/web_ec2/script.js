document.addEventListener('DOMContentLoaded', () => {
    // Insertar logo ALB
    const albLogoContainer = document.getElementById('alb-logo-container');
    albLogoContainer.innerHTML = `
        <svg viewBox="0 0 256 304" fill="none">
            <path d="M128 0C57.3 0 0 57.3 0 128s57.3 128 128 128 128-57.3 128-128S198.7 0 128 0zm0 224c-52.9 0-96-43.1-96-96s43.1-96 96-96 96 43.1 96 96-43.1 96-96 96zm0-160c-35.3 0-64 28.7-64 64s28.7 64 64 64 64-28.7 64-64-28.7-64-64-64zm0 96c-17.7 0-32-14.3-32-32s14.3-32 32-32 32 14.3 32 32-14.3 32-32 32z" fill="white"/>
            <path d="M128 64c-35.3 0-64 28.7-64 64s28.7 64 64 64 64-28.7 64-64-28.7-64-64-64zm0 96c-17.7 0-32-14.3-32-32s14.3-32 32-32 32 14.3 32 32-14.3 32-32 32z" fill="#FF9900"/>
        </svg>
    `;

    const elements = {
        instanceId: document.getElementById('instance-id'),
        publicIp: document.getElementById('public-ip'),
        az: document.getElementById('availability-zone'),
        instanceType: document.getElementById('instance-type'),
        timestamp: document.getElementById('timestamp')
    };
    
    const refreshBtn = document.getElementById('refresh-btn');
    const detailsBtn = document.getElementById('details-btn');

    function updateUI(data) {
        const isAWS = data.isAWS;
        const badge = (text) => `<span class="status-badge ${isAWS ? 'status-aws' : 'status-simulated'}">${isAWS ? 'AWS' : 'Simulado'}</span>`;
        
        elements.instanceId.innerHTML = `${data.instanceId} ${badge()}`;
        elements.publicIp.innerHTML = `${data.publicIp} ${badge()}`;
        elements.az.innerHTML = `${data.az} ${badge()}`;
        elements.instanceType.innerHTML = `${data.instanceType} ${badge()}`;
        elements.timestamp.textContent = new Date().toLocaleString();
    }

    function showLoading() {
        Object.values(elements).forEach(el => {
            if (el.id !== 'timestamp') {
                el.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Cargando...';
            }
        });
    }

    function showError() {
        const simulatedData = {
            instanceId: 'i-1234567890',
            publicIp: '203.0.113.45',
            az: 'us-east-1a',
            instanceType: 't3.medium',
            isAWS: false
        };
        updateUI(simulatedData);
    }

    async function fetchMetadata() {
        try {
            showLoading();

            const response = await fetch('metadata.php');
            if (!response.ok) throw new Error('Error en el servidor');
            
            const data = await response.json();
            updateUI(data);

            // Feedback visual
            refreshBtn.innerHTML = `<i class="fas fa-check"></i> Actualizado`;
            refreshBtn.style.backgroundColor = '#10b981';
            
            setTimeout(() => {
                refreshBtn.innerHTML = `<i class="fas fa-sync-alt"></i> Actualizar`;
                refreshBtn.style.backgroundColor = '';
            }, 2000);

        } catch (error) {
            console.error('Error:', error);
            showError();
            
            refreshBtn.innerHTML = `<i class="fas fa-exclamation-triangle"></i> Error`;
            refreshBtn.style.backgroundColor = '#ef4444';
        }
    }

    detailsBtn.addEventListener('click', () => {
        alert('Este panel muestra la instancia EC2 actual que está sirviendo tu solicitud. Si estás usando un Application Load Balancer (ALB), al actualizar deberías ver diferentes Instance IDs cuando el balanceador distribuye el tráfico entre múltiples instancias.');
    });

    // Cargar datos al inicio
    fetchMetadata();
    
    // Configurar el botón de actualización
    refreshBtn.addEventListener('click', fetchMetadata);
    
    // Actualizar automáticamente cada 30 segundos
    setInterval(fetchMetadata, 30000);
});
