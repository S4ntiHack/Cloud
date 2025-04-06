#!/bin/bash
# Script para desplegar infraestructura LAMP con nombres personalizables

set -euo pipefail

# =============================================
# VARIABLE GLOBAL PARA NOMBRES DE RECURSOS
# Cambiar este valor para personalizar todos los nombres
PROJECT_NAME="Proyecto"
# =============================================

# --- Configuración AWS ---
export AWS_DEFAULT_REGION="us-east-1"
export AWS_PAGER=""

# --- Generación de sufijo único ---
UNIQUE_SUFFIX=$(echo $RANDOM | md5sum | head -c 8)
FULL_NAME="${PROJECT_NAME}-${UNIQUE_SUFFIX}"

# --- Configuración de recursos ---
KEY_NAME="${FULL_NAME}-key"
INSTANCE_TYPE="t2.micro"
AMI_ID="ami-0fc5d935ebf8bc3bc"  # Ubuntu 24.04 LTS

# Nombres derivados de la variable global
SG_NAME="${FULL_NAME}-sg"
INSTANCE_NAME="${FULL_NAME}-instance"
AMI_NAME="${FULL_NAME}-ami"
AMI_DESCRIPTION="AMI para ${FULL_NAME}"

# --- Funciones ---
handle_error() {
    echo "[ERROR] Línea $1: Comando '$2' falló"
    cleanup
    exit 1
}

wait_for_status() {
    local cmd="$1"
    local desired_status="$2"
    local timeout="${3:-300}"
    local interval="${4:-10}"
    local start_time=$(date +%s)
    
    echo -n "Esperando estado '$desired_status'..."
    while true; do
        current_status=$(eval "$cmd" 2>/dev/null || echo "error")
        if [[ "$current_status" == "$desired_status" ]]; then
            echo " OK"
            return 0
        fi
        
        if (( $(date +%s) - start_time > timeout )); then
            echo " TIMEOUT"
            return 1
        fi
        
        echo -n "."
        sleep "$interval"
    done
}

cleanup() {
    echo "Iniciando limpieza de recursos de ${FULL_NAME}..."
    
    # Orden de eliminación seguro
    [[ -n "${IMAGE_ID:-}" ]] && { aws ec2 deregister-image --image-id "$IMAGE_ID" && echo "AMI ${IMAGE_ID} eliminada"; } || echo "Error eliminando AMI"
    
    [[ -n "${INSTANCE_ID:-}" ]] && { 
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" 
        wait_for_status "aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Instances[0].State.Name' --output text" "terminated" 300
        echo "Instancia ${INSTANCE_ID} terminada"
    }
    
    [[ -n "${ALLOCATION_ID:-}" ]] && { aws ec2 release-address --allocation-id "$ALLOCATION_ID" && echo "IP elástica liberada"; }
    
    [[ -n "${NAT_GW_ID:-}" ]] && { 
        aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_GW_ID"
        echo "NAT Gateway ${NAT_GW_ID} en eliminación"
    }
    
    sleep 30
    
    [[ -n "${EIP_ALLOC_ID:-}" ]] && { aws ec2 release-address --allocation-id "$EIP_ALLOC_ID" && echo "EIP liberado"; }
    
    [[ -n "${PRIVATE_RT_ID:-}" ]] && { aws ec2 delete-route-table --route-table-id "$PRIVATE_RT_ID" && echo "Tabla de rutas privada eliminada"; }
    
    [[ -n "${PUBLIC_RT_ID:-}" ]] && { aws ec2 delete-route-table --route-table-id "$PUBLIC_RT_ID" && echo "Tabla de rutas pública eliminada"; }
    
    [[ -n "${PUBLIC_SUBNET_ID:-}" ]] && { aws ec2 delete-subnet --subnet-id "$PUBLIC_SUBNET_ID" && echo "Subred pública eliminada"; }
    
    [[ -n "${PRIVATE_SUBNET_ID:-}" ]] && { aws ec2 delete-subnet --subnet-id "$PRIVATE_SUBNET_ID" && echo "Subred privada eliminada"; }
    
    [[ -n "${IGW_ID:-}" ]] && { 
        aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
        aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"
        echo "Internet Gateway eliminado"
    }
    
    [[ -n "${SG_ID:-}" ]] && { aws ec2 delete-security-group --group-id "$SG_ID" && echo "Security Group eliminado"; }
    
    [[ -n "${VPC_ID:-}" ]] && { aws ec2 delete-vpc --vpc-id "$VPC_ID" && echo "VPC eliminada"; }
    
    [[ -n "${KEY_NAME:-}" ]] && { aws ec2 delete-key-pair --key-name "$KEY_NAME" && echo "Key pair eliminado"; }
}

# Configurar traps
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR
trap cleanup SIGINT

# --- 1. Crear par de claves ---
echo "Creando par de claves ${KEY_NAME}..."
aws ec2 create-key-pair --key-name "$KEY_NAME" --query 'KeyMaterial' --output text > "${KEY_NAME}.pem"
chmod 400 "${KEY_NAME}.pem"

# --- 2. Crear VPC ---
echo "Creando VPC para ${FULL_NAME}..."
VPC_ID=$(aws ec2 create-vpc --cidr-block "10.0.0.0/16" --amazon-provided-ipv6-cidr-block --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="${FULL_NAME}-vpc"

# --- 3. Configurar red ---
echo "Configurando red para ${FULL_NAME}..."

# Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
aws ec2 create-tags --resources "$IGW_ID" --tags Key=Name,Value="${FULL_NAME}-igw"

# Subred pública
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "10.0.1.0/24" --availability-zone "${AWS_DEFAULT_REGION}a" --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --subnet-id "$PUBLIC_SUBNET_ID" --map-public-ip-on-launch
aws ec2 create-tags --resources "$PUBLIC_SUBNET_ID" --tags Key=Name,Value="${FULL_NAME}-pub-subnet"

# Tabla de rutas pública
PUBLIC_RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$PUBLIC_RT_ID" --destination-cidr-block "0.0.0.0/0" --gateway-id "$IGW_ID"
aws ec2 associate-route-table --route-table-id "$PUBLIC_RT_ID" --subnet-id "$PUBLIC_SUBNET_ID"
aws ec2 create-tags --resources "$PUBLIC_RT_ID" --tags Key=Name,Value="${FULL_NAME}-pub-rt"

# NAT Gateway
EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
NAT_GW_ID=$(aws ec2 create-nat-gateway --subnet-id "$PUBLIC_SUBNET_ID" --allocation-id "$EIP_ALLOC_ID" --query 'NatGateway.NatGatewayId' --output text)
aws ec2 create-tags --resources "$NAT_GW_ID" --tags Key=Name,Value="${FULL_NAME}-nat"
echo "Esperando NAT Gateway..."
wait_for_status "aws ec2 describe-nat-gateways --nat-gateway-ids $NAT_GW_ID --query 'NatGateways[0].State' --output text" "available" 600

# Subred privada
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "10.0.2.0/24" --availability-zone "${AWS_DEFAULT_REGION}a" --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources "$PRIVATE_SUBNET_ID" --tags Key=Name,Value="${FULL_NAME}-priv-subnet"

# Tabla de rutas privada
PRIVATE_RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$PRIVATE_RT_ID" --destination-cidr-block "0.0.0.0/0" --nat-gateway-id "$NAT_GW_ID"
aws ec2 associate-route-table --route-table-id "$PRIVATE_RT_ID" --subnet-id "$PRIVATE_SUBNET_ID"
aws ec2 create-tags --resources "$PRIVATE_RT_ID" --tags Key=Name,Value="${FULL_NAME}-priv-rt"

# --- 4. Security Group ---
echo "Creando Security Group ${SG_NAME}..."
SG_ID=$(aws ec2 create-security-group --group-name "$SG_NAME" --description "Security Group para ${FULL_NAME}" --vpc-id "$VPC_ID" --query 'GroupId' --output text)

# Reglas de entrada
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 443 --cidr "0.0.0.0/0"

# --- 5. User Data ---
cat > user-data-${FULL_NAME}.sh << EOF
#!/bin/bash
apt-get update -y
apt-get install -y apache2 mysql-server php libapache2-mod-php php-mysql
systemctl enable apache2
systemctl start apache2
echo "<?php phpinfo(); ?>" > /var/www/html/info.php
chown -R www-data:www-data /var/www/html
EOF

# --- 6. Lanzar instancia ---
echo "Lanzando instancia ${INSTANCE_NAME}..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --subnet-id "$PUBLIC_SUBNET_ID" \
    --user-data file://user-data-${FULL_NAME}.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

# --- 7. IP Elástica ---
ELASTIC_IP=$(aws ec2 allocate-address --domain vpc --query 'PublicIp' --output text)
ALLOCATION_ID=$(aws ec2 describe-addresses --public-ips "$ELASTIC_IP" --query 'Addresses[0].AllocationId' --output text)
aws ec2 associate-address --instance-id "$INSTANCE_ID" --public-ip "$ELASTIC_IP"

# --- 8. Mostrar resultados ---
echo -e "\n--- DESPLIEGUE COMPLETADO: ${FULL_NAME} ;) ---"
echo "Instancia ID: $INSTANCE_ID"
echo "IP Pública: $ELASTIC_IP"
echo "Acceso SSH: ssh -i ${KEY_NAME}.pem ubuntu@$ELASTIC_IP"
echo "URL prueba: http://$ELASTIC_IP/info.php"

# Guardar información
cat > "deployment-info-${FULL_NAME}.txt" << EOF
=== ${FULL_NAME} ===
Fecha: $(date)
VPC: $VPC_ID
Subred Pública: $PUBLIC_SUBNET_ID
Subred Privada: $PRIVATE_SUBNET_ID
Instancia: $INSTANCE_ID
IP: $ELASTIC_IP
Clave SSH: ${KEY_NAME}.pem

=== Comandos útiles ===
Conectar SSH: ssh -i ${KEY_NAME}.pem ubuntu@$ELASTIC_IP
Ver estado instancia: aws ec2 describe-instances --instance-ids $INSTANCE_ID
Eliminar todo: Ejecutar cleanup manualmente
EOF

echo "Información guardada en deployment-info-${FULL_NAME}.txt"
