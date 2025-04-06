#!/bin/bash

#=================================
# Autor --> Santiago Montenegro
#=================================

# Configuración general
VPC_NAME="proof-vpc-infra"
VPC_IPV4_CIDR="170.10.0.0/16"
PUBLIC_SUBNET_CIDR="170.10.10.0/24"
PRIVATE_SUBNET_CIDR="170.10.20.0/24"
KEY_PAIR_NAME="vockey"
INSTANCE_TYPE="t3.medium"
DEFAULT_REGION="us-east-1"

# =========================================
# FUNCIONES DE LIMPIEZA
# =========================================

cleanup_resources() {
    echo "ERROR: Limpiando recursos debido a fallo..."
    
    # Eliminar instancias primero
    for instance in $(aws ec2 describe-instances --filters "Name=tag:Name,Values=proof-*" --query "Reservations[].Instances[].InstanceId" --output text --region $REGION 2>/dev/null); do
        echo "Eliminando instancia $instance..."
        aws ec2 terminate-instances --instance-ids $instance --region $REGION >/dev/null
        aws ec2 wait instance-terminated --instance-ids $instance --region $REGION
    done

    # Eliminar NAT Gateways
    for nat in $(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=proof-natgw" --query "NatGateways[?State!='deleted'].NatGatewayId" --output text --region $REGION 2>/dev/null); do
        echo "Eliminando NAT Gateway $nat..."
        aws ec2 delete-nat-gateway --nat-gateway-id $nat --region $REGION >/dev/null
        aws ec2 wait nat-gateway-deleted --nat-gateway-ids $nat --region $REGION
    done

    # Eliminar EIPs
    for eip in $(aws ec2 describe-addresses --filters "Name=tag:Name,Values=proof-natgw-eip" --query "Addresses[].AllocationId" --output text --region $REGION 2>/dev/null); do
        echo "Liberando EIP $eip..."
        aws ec2 release-address --allocation-id $eip --region $REGION >/dev/null || true
    done

    # Eliminar subredes
    for subnet in $(aws ec2 describe-subnets --filters "Name=tag:Name,Values=proof-subnet-*" --query "Subnets[].SubnetId" --output text --region $REGION 2>/dev/null); do
        echo "Eliminando subred $subnet..."
        aws ec2 delete-subnet --subnet-id $subnet --region $REGION >/dev/null || true
    done

    # Eliminar route tables
    for rt in $(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=proof-rt-*" --query "RouteTables[].RouteTableId" --output text --region $REGION 2>/dev/null); do
        echo "Eliminando tabla de rutas $rt..."
        aws ec2 delete-route-table --route-table-id $rt --region $REGION >/dev/null || true
    done

    # Eliminar Internet Gateways
    for igw in $(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=${VPC_NAME}-igw" --query "InternetGateways[].InternetGatewayId" --output text --region $REGION 2>/dev/null); do
        echo "Desasociando y eliminando IGW $igw..."
        aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID --region $REGION >/dev/null || true
        aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $REGION >/dev/null || true
    done

    # Eliminar security groups
    for sg in $(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=proof-sg-*" --query "SecurityGroups[].GroupId" --output text --region $REGION 2>/dev/null); do
        echo "Eliminando grupo de seguridad $sg..."
        aws ec2 delete-security-group --group-id $sg --region $REGION >/dev/null || true
    done

    # Eliminar VPC
    if [ -n "$VPC_ID" ]; then
        echo "Eliminando VPC $VPC_ID..."
        aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION >/dev/null || true
    fi

    exit 1
}

# =========================================
# VERIFICACIONES INICIALES
# =========================================

if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI no está instalado." >&2
    exit 1
fi

if ! aws configure get aws_access_key_id &> /dev/null; then
    echo "ERROR: AWS CLI no está configurado." >&2
    exit 1
fi

REGION=${1:-$(aws configure get region)}
REGION=${REGION:-$DEFAULT_REGION}
echo "Usando región: $REGION" >&2

# =========================================
# FUNCIONES PRINCIPALES
# =========================================

create_vpc() {
    echo "Creando VPC..." >&2
    local vpc_id=$(aws ec2 create-vpc \
        --cidr-block "$VPC_IPV4_CIDR" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]" \
        --query 'Vpc.VpcId' \
        --output text \
        --region $REGION)

    [ -z "$vpc_id" ] && { echo "ERROR: No se pudo crear VPC" >&2; cleanup_resources; }

    # Habilitar DNS
    aws ec2 modify-vpc-attribute \
        --vpc-id "$vpc_id" \
        --enable-dns-hostnames \
        --region $REGION

    echo "$vpc_id"
}

create_public_subnet() {
    local vpc_id=$1
    echo "Creando subred pública..." >&2
    
    local subnet_id=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "$PUBLIC_SUBNET_CIDR" \
        --availability-zone "${REGION}a" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=proof-subnet-public}]" \
        --query 'Subnet.SubnetId' \
        --output text \
        --region $REGION)

    [ -z "$subnet_id" ] && { echo "ERROR: No se pudo crear subred pública" >&2; cleanup_resources; }

    # Habilitar auto-asignación de IP pública
    aws ec2 modify-subnet-attribute \
        --subnet-id "$subnet_id" \
        --map-public-ip-on-launch \
        --region $REGION

    echo "$subnet_id"
}

create_private_subnet() {
    local vpc_id=$1
    echo "Creando subred privada..." >&2
    
    local subnet_id=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "$PRIVATE_SUBNET_CIDR" \
        --availability-zone "${REGION}a" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=proof-subnet-private}]" \
        --query 'Subnet.SubnetId' \
        --output text \
        --region $REGION)

    [ -z "$subnet_id" ] && { echo "ERROR: No se pudo crear subred privada" >&2; cleanup_resources; }

    echo "$subnet_id"
}

create_igw() {
    local vpc_id=$1
    echo "Creando Internet Gateway..." >&2
    local igw_id=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw}]" \
        --query 'InternetGateway.InternetGatewayId' \
        --output text \
        --region $REGION)

    [ -z "$igw_id" ] && { echo "ERROR: No se pudo crear IGW" >&2; cleanup_resources; }

    aws ec2 attach-internet-gateway \
        --internet-gateway-id "$igw_id" \
        --vpc-id "$vpc_id" \
        --region $REGION

    echo "$igw_id"
}

create_nat_gateway() {
    local subnet_id=$1
    echo "Creando NAT Gateway..." >&2
    
    # Asignar EIP
    local eip_id=$(aws ec2 allocate-address \
        --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=proof-natgw-eip}]" \
        --query 'AllocationId' \
        --output text \
        --region $REGION)

    [ -z "$eip_id" ] && { echo "ERROR: No se pudo asignar EIP" >&2; cleanup_resources; }

    # Crear NAT Gateway
    local nat_id=$(aws ec2 create-nat-gateway \
        --subnet-id "$subnet_id" \
        --allocation-id "$eip_id" \
        --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=proof-natgw}]" \
        --query 'NatGateway.NatGatewayId' \
        --output text \
        --region $REGION)

    [ -z "$nat_id" ] && { echo "ERROR: No se pudo crear NAT Gateway" >&2; cleanup_resources; }

    echo "Esperando a que NAT Gateway esté disponible (puede tardar varios minutos)..." >&2
    aws ec2 wait nat-gateway-available --nat-gateway-ids "$nat_id" --region $REGION
    echo "$nat_id"
}

configure_route_tables() {
    local vpc_id=$1 igw_id=$2 nat_id=$3 public_subnet_id=$4 private_subnet_id=$5
    echo "Configurando tablas de ruta..." >&2
    
    # Tabla de rutas pública
    local public_rt_id=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=proof-rt-public}]" \
        --query 'RouteTable.RouteTableId' \
        --output text \
        --region $REGION)

    aws ec2 associate-route-table \
        --route-table-id "$public_rt_id" \
        --subnet-id "$public_subnet_id" \
        --region $REGION >/dev/null

    aws ec2 create-route \
        --route-table-id "$public_rt_id" \
        --destination-cidr-block "0.0.0.0/0" \
        --gateway-id "$igw_id" \
        --region $REGION >/dev/null

    # Tabla de rutas privada
    local private_rt_id=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=proof-rt-private}]" \
        --query 'RouteTable.RouteTableId' \
        --output text \
        --region $REGION)

    aws ec2 associate-route-table \
        --route-table-id "$private_rt_id" \
        --subnet-id "$private_subnet_id" \
        --region $REGION >/dev/null

    aws ec2 create-route \
        --route-table-id "$private_rt_id" \
        --destination-cidr-block "0.0.0.0/0" \
        --nat-gateway-id "$nat_id" \
        --region $REGION >/dev/null

    echo "$public_rt_id $private_rt_id"
}

create_security_groups() {
    local vpc_id=$1 public_subnet_cidr=$2
    echo "Creando grupos de seguridad..." >&2
    
    # Grupo público (acceso SSH y HTTP/HTTPS desde cualquier lugar)
    local public_sg=$(aws ec2 create-security-group \
        --group-name "proof-sg-public" \
        --description "Public security group for SSH and HTTP/HTTPS" \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=proof-sg-public}]" \
        --query 'GroupId' \
        --output text \
        --region $REGION)

    [ -z "$public_sg" ] && { echo "ERROR: No se pudo crear grupo de seguridad público" >&2; cleanup_resources; }

    # Reglas para grupo público
    # SSH (puerto 22) desde cualquier lugar
    aws ec2 authorize-security-group-ingress \
        --group-id "$public_sg" \
        --protocol tcp --port 22 --cidr 0.0.0.0/0 \
        --region $REGION >/dev/null
        
    # HTTP (puerto 80) desde cualquier lugar
    aws ec2 authorize-security-group-ingress \
        --group-id "$public_sg" \
        --protocol tcp --port 80 --cidr 0.0.0.0/0 \
        --region $REGION >/dev/null
        
    # HTTPS (puerto 443) desde cualquier lugar (SOLO para Ubuntu público)
    aws ec2 authorize-security-group-ingress \
        --group-id "$public_sg" \
        --protocol tcp --port 443 --cidr 0.0.0.0/0 \
        --region $REGION >/dev/null
        
    # RDP (puerto 3389) desde cualquier lugar (para Windows)
    aws ec2 authorize-security-group-ingress \
        --group-id "$public_sg" \
        --protocol tcp --port 3389 --cidr 0.0.0.0/0 \
        --region $REGION >/dev/null

    # DNS (puerto 53) UDP desde cualquier lugar para el servidor Ubuntu
    aws ec2 authorize-security-group-ingress \
        --group-id "$public_sg" \
        --protocol udp --port 53 --cidr 0.0.0.0/0 \
        --region $REGION >/dev/null

    # DNS (puerto 53) TCP desde cualquier lugar para el servidor Ubuntu
    aws ec2 authorize-security-group-ingress \
        --group-id "$public_sg" \
        --protocol tcp --port 53 --cidr 0.0.0.0/0 \
        --region $REGION >/dev/null

    # Grupo privado (solo acceso desde subred pública)
    local private_sg=$(aws ec2 create-security-group \
        --group-name "proof-sg-private" \
        --description "Private security group" \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=proof-sg-private}]" \
        --query 'GroupId' \
        --output text \
        --region $REGION)

    [ -z "$private_sg" ] && { echo "ERROR: No se pudo crear grupo de seguridad privado" >&2; cleanup_resources; }

    # SSH desde subred pública
    aws ec2 authorize-security-group-ingress \
        --group-id "$private_sg" \
        --protocol tcp --port 22 --cidr "$public_subnet_cidr" \
        --region $REGION >/dev/null
        
    # RDP desde subred pública (para Windows)
    aws ec2 authorize-security-group-ingress \
        --group-id "$private_sg" \
        --protocol tcp --port 3389 --cidr "$public_subnet_cidr" \
        --region $REGION >/dev/null
        
    # Todo el tráfico interno dentro de la VPC
    aws ec2 authorize-security-group-ingress \
        --group-id "$private_sg" \
        --protocol all --port -1 --cidr "$VPC_IPV4_CIDR" \
        --region $REGION >/dev/null

    echo "$public_sg $private_sg"
}

launch_instance() {
    local name=$1 ami=$2 subnet=$3 sg=$4 is_public=$5
    echo "Lanzando instancia $name..." >&2

    # User data para instancias Ubuntu en subred pública
    local user_data=""
    if [[ "$name" == "proof-ubuntu-public" ]]; then
        user_data="#!/bin/bash
apt-get update -y
apt-get install -y apache2 mysql-server php mysql-client libapache2-mod-php php-mysql bind9
systemctl enable apache2
systemctl start apache2
echo \"<?php phpinfo(); ?>\" > /var/www/html/info.php
chown -R www-data:www-data /var/www/html"
        
        # Crear archivo temporal para user data
        local temp_file=$(mktemp)
        echo "$user_data" > "$temp_file"
    fi

    local instance_id=$(aws ec2 run-instances \
        --image-id "$ami" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_PAIR_NAME" \
        --subnet-id "$subnet" \
        --security-group-ids "$sg" \
        $( [ "$is_public" = "true" ] && echo "--associate-public-ip-address" ) \
        $( [ -n "$user_data" ] && echo "--user-data" "file://$temp_file" ) \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$name}]" \
        --query 'Instances[0].InstanceId' \
        --output text \
        --region $REGION)

    # Eliminar archivo temporal si existe
    [ -n "$temp_file" ] && rm -f "$temp_file"

    [ -z "$instance_id" ] && { echo "ERROR: No se pudo lanzar instancia $name" >&2; cleanup_resources; }

    # Habilitar DNS para instancias públicas
    if [ "$is_public" = "true" ]; then
        aws ec2 modify-instance-attribute \
            --instance-id "$instance_id" \
            --no-source-dest-check \
            --region $REGION >/dev/null
    fi

    echo "Esperando a que la instancia $name esté disponible..." >&2
    aws ec2 wait instance-running --instance-ids "$instance_id" --region $REGION
    
    # Espera adicional para asegurar IP pública
    if [ "$is_public" = "true" ]; then
        sleep 20
    fi

    # Obtener información de la instancia con reintentos
    local instance_info
    for i in {1..5}; do
        instance_info=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].[InstanceId,PublicIpAddress,PrivateIpAddress]' \
            --output text \
            --region $REGION)
        
        # Verificar que tenemos la IP pública si es instancia pública
        if [ "$is_public" != "true" ] || [ -n "$(echo "$instance_info" | awk '{print $2}')" ]; then
            break
        fi
        sleep 10
    done

    # Si es instancia pública y no tiene IP, asignar Elastic IP
    if [ "$is_public" = "true" ] && [ -z "$(echo "$instance_info" | awk '{print $2}')" ]; then
        echo "Asignando Elastic IP a instancia pública $name..." >&2
        local eip_allocation=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text --region $REGION)
        aws ec2 associate-address --instance-id "$instance_id" --allocation-id "$eip_allocation" --region $REGION >/dev/null
        instance_info=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].[InstanceId,PublicIpAddress,PrivateIpAddress]' \
            --output text \
            --region $REGION)
    fi

    echo "$instance_info"
}

# =========================================
# FLUJO PRINCIPAL
# =========================================

main() {
    trap cleanup_resources ERR INT TERM

    echo "=== INICIANDO DESPLIEGUE COMPLETO DESDE CERO ==="

    # 1. Crear VPC
    echo -e "\nPaso 1/7: Creando VPC..."
    VPC_ID=$(create_vpc)

    # 2. Crear subredes
    echo -e "\nPaso 2/7: Creando subred pública..."
    PUBLIC_SUBNET_ID=$(create_public_subnet "$VPC_ID")

    echo -e "\nPaso 3/7: Creando subred privada..."
    PRIVATE_SUBNET_ID=$(create_private_subnet "$VPC_ID")

    # 3. Internet Gateway
    echo -e "\nPaso 4/7: Configurando Internet Gateway..."
    IGW_ID=$(create_igw "$VPC_ID")

    # 4. NAT Gateway
    echo -e "\nPaso 5/7: Configurando NAT Gateway..."
    NAT_GW_ID=$(create_nat_gateway "$PUBLIC_SUBNET_ID")

    # 5. Tablas de ruta
    echo -e "\nPaso 6/7: Configurando tablas de ruta..."
    read PUBLIC_RT_ID PRIVATE_RT_ID <<< $(configure_route_tables "$VPC_ID" "$IGW_ID" "$NAT_GW_ID" "$PUBLIC_SUBNET_ID" "$PRIVATE_SUBNET_ID")

    # 6. Grupos de seguridad
    echo -e "\nPaso 7/7: Configurando grupos de seguridad..."
    read PUBLIC_SG_ID PRIVATE_SG_ID <<< $(create_security_groups "$VPC_ID" "$PUBLIC_SUBNET_CIDR")

    # 7. Instancias EC2
    echo -e "\nObteniendo AMIs más recientes..."
    WINDOWS_AMI=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=Windows_Server-2022-English-Full-Base*" \
        --query "sort_by(Images, &CreationDate)[-1].ImageId" \
        --output text \
        --region $REGION)

    UBUNTU_AMI=$(aws ec2 describe-images \
        --owners 099720109477 \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
        --query "sort_by(Images, &CreationDate)[-1].ImageId" \
        --output text \
        --region $REGION)

    echo -e "\nLanzando instancias públicas..."
    WINDOWS_PUBLIC_INFO=$(launch_instance "proof-win-public" "$WINDOWS_AMI" "$PUBLIC_SUBNET_ID" "$PUBLIC_SG_ID" "true")
    UBUNTU_PUBLIC_INFO=$(launch_instance "proof-ubuntu-public" "$UBUNTU_AMI" "$PUBLIC_SUBNET_ID" "$PUBLIC_SG_ID" "true")

    echo -e "\nLanzando instancias privadas..."
    WINDOWS_PRIVATE_INFO=$(launch_instance "proof-win-private" "$WINDOWS_AMI" "$PRIVATE_SUBNET_ID" "$PRIVATE_SG_ID" "false")
    UBUNTU_PRIVATE_INFO=$(launch_instance "proof-ubuntu-private" "$UBUNTU_AMI" "$PRIVATE_SUBNET_ID" "$PRIVATE_SG_ID" "false")

    # Mostrar resumen
    echo -e "\n=== DESPLIEGUE COMPLETADO CON ÉXITO ;) ==="
    echo "VPC ID: $VPC_ID"
    echo "Subred Pública: $PUBLIC_SUBNET_ID"
    echo "Subred Privada: $PRIVATE_SUBNET_ID"
    echo -e "\nInstancias Públicas:"
    echo "- Windows: $(echo "$WINDOWS_PUBLIC_INFO" | awk '{print $1}') - IP Pública: $(echo "$WINDOWS_PUBLIC_INFO" | awk '{print $2}')"
    echo "- Ubuntu: $(echo "$UBUNTU_PUBLIC_INFO" | awk '{print $1}') - IP Pública: $(echo "$UBUNTU_PUBLIC_INFO" | awk '{print $2}')"
    echo -e "\nInstancias Privadas (solo accesibles desde la subred pública $PUBLIC_SUBNET_CIDR):"
    echo "- Windows: $(echo "$WINDOWS_PRIVATE_INFO" | awk '{print $1}') - IP Privada: $(echo "$WINDOWS_PRIVATE_INFO" | awk '{print $3}')"
    echo "- Ubuntu: $(echo "$UBUNTU_PRIVATE_INFO" | awk '{print $1}') - IP Privada: $(echo "$UBUNTU_PRIVATE_INFO" | awk '{print $3}')"
    echo -e "\nPara conectarte:"
    echo "SSH a Ubuntu pública: ssh -i $KEY_PAIR_NAME.pem ubuntu@$(echo "$UBUNTU_PUBLIC_INFO" | awk '{print $2}')"
    echo "HTTPS a Ubuntu pública: https://$(echo "$UBUNTU_PUBLIC_INFO" | awk '{print $2}')"
    echo "Windows pública: aws ec2 get-password-data --instance-id $(echo "$WINDOWS_PUBLIC_INFO" | awk '{print $1}') --priv-launch-key $KEY_PAIR_NAME --region $REGION"
}

# Ejecutar el flujo principal
main
