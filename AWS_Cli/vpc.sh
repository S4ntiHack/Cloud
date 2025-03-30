#!/bin/bash

#===============================
# Author --> Santiago Montenegro
#===============================

# Configuración
VPC_NAME="proof-vpc-infra"
VPC_IPV4_CIDR="170.10.0.0/16"
PUBLIC_SUBNET_CIDR="170.10.10.0/24"
PRIVATE_SUBNET_CIDR="170.10.20.0/24"
DEFAULT_REGION="us-east-1"

# Verificar AWS CLI
if ! aws configure get aws_access_key_id &>/dev/null; then
    echo "ERROR: AWS CLI no está configurado. Ejecuta 'aws configure' primero."
    exit 1
fi

# Obtener región
REGION=${1:-$(aws configure get region)}
REGION=${REGION:-$DEFAULT_REGION}
echo "Usando región: $REGION"

# 1. Crear VPC
echo "Creando VPC..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $VPC_IPV4_CIDR \
    --amazon-provided-ipv6-cidr-block \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}}]" \
    --region $REGION \
    --query 'Vpc.VpcId' \
    --output text)

if [ -z "$VPC_ID" ]; then
    echo "ERROR: No se pudo crear la VPC"
    exit 1
fi
echo "VPC creada con ID: $VPC_ID"

# Habilitar DNS
aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-support "{\"Value\":true}" \
    --region $REGION

aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-hostnames "{\"Value\":true}" \
    --region $REGION

# 2. Crear Internet Gateway
echo "Creando Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=proof-igw-main}]" \
    --region $REGION \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

aws ec2 attach-internet-gateway \
    --vpc-id $VPC_ID \
    --internet-gateway-id $IGW_ID \
    --region $REGION

# 3. Crear Elastic IP para NAT Gateway
echo "Creando Elastic IP para NAT Gateway..."
ALLOCATION_ID=$(aws ec2 allocate-address \
    --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=proof-eip-natgw}]" \
    --region $REGION \
    --query 'AllocationId' \
    --output text)

# 4. Crear subred pública
echo "Creando subred pública ${PUBLIC_SUBNET_CIDR}..."
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $PUBLIC_SUBNET_CIDR \
    --availability-zone "${REGION}a" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=proof-subnet-public}]" \
    --region $REGION \
    --query 'Subnet.SubnetId' \
    --output text)

# Habilitar asignación automática de IPs públicas
aws ec2 modify-subnet-attribute \
    --subnet-id $PUBLIC_SUBNET_ID \
    --map-public-ip-on-launch \
    --region $REGION

# 5. Crear subred privada
echo "Creando subred privada ${PRIVATE_SUBNET_CIDR}..."
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $PRIVATE_SUBNET_CIDR \
    --availability-zone "${REGION}b" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=proof-subnet-private}]" \
    --region $REGION \
    --query 'Subnet.SubnetId' \
    --output text)

# 6. Crear NAT Gateway en la subred pública
echo "Creando NAT Gateway en la subred pública..."
NAT_GW_ID=$(aws ec2 create-nat-gateway \
    --subnet-id $PUBLIC_SUBNET_ID \
    --allocation-id $ALLOCATION_ID \
    --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=proof-natgw-main}]" \
    --region $REGION \
    --query 'NatGateway.NatGatewayId' \
    --output text)

echo "Esperando a que el NAT Gateway esté disponible..."
aws ec2 wait nat-gateway-available \
    --nat-gateway-ids $NAT_GW_ID \
    --region $REGION

# 7. Crear tabla de rutas pública
echo "Creando tabla de rutas pública..."
PUBLIC_RT_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=proof-rt-public}]" \
    --region $REGION \
    --query 'RouteTable.RouteTableId' \
    --output text)

# Añadir ruta a Internet Gateway
aws ec2 create-route \
    --route-table-id $PUBLIC_RT_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID \
    --region $REGION

# Asociar tabla de rutas pública con subred pública
aws ec2 associate-route-table \
    --subnet-id $PUBLIC_SUBNET_ID \
    --route-table-id $PUBLIC_RT_ID \
    --region $REGION

# 8. Crear tabla de rutas privada
echo "Creando tabla de rutas privada..."
PRIVATE_RT_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=proof-rt-private}]" \
    --region $REGION \
    --query 'RouteTable.RouteTableId' \
    --output text)

# Añadir ruta a NAT Gateway
aws ec2 create-route \
    --route-table-id $PRIVATE_RT_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id $NAT_GW_ID \
    --region $REGION

# Asociar tabla de rutas privada con subred privada
aws ec2 associate-route-table \
    --subnet-id $PRIVATE_SUBNET_ID \
    --route-table-id $PRIVATE_RT_ID \
    --region $REGION

# 9. Crear grupos de seguridad básicos
# Grupo de seguridad público
PUBLIC_SG_ID=$(aws ec2 create-security-group \
    --group-name "proof-sg-public" \
    --description "Security group for public instances" \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=proof-sg-public}]" \
    --region $REGION \
    --query 'GroupId' \
    --output text)

# Grupo de seguridad privado
PRIVATE_SG_ID=$(aws ec2 create-security-group \
    --group-name "proof-sg-private" \
    --description "Security group for private instances" \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=proof-sg-private}]" \
    --region $REGION \
    --query 'GroupId' \
    --output text)

echo "Configuración completada:"
echo "========================================"
echo "VPC:"
echo "  ID: $VPC_ID"
echo "  Nombre: $VPC_NAME"
echo "  CIDR: $VPC_IPV4_CIDR"
echo ""
echo "Subredes:"
echo "  Pública: $PUBLIC_SUBNET_ID (${PUBLIC_SUBNET_CIDR})"
echo "  Privada: $PRIVATE_SUBNET_ID (${PRIVATE_SUBNET_CIDR})"
echo ""
echo "Gateways:"
echo "  Internet Gateway: $IGW_ID"
echo "  NAT Gateway: $NAT_GW_ID"
echo ""
echo "Tablas de ruta:"
echo "  Pública: $PUBLIC_RT_ID"
echo "  Privada: $PRIVATE_RT_ID"
echo ""
echo "Grupos de seguridad:"
echo "  Público: $PUBLIC_SG_ID"
echo "  Privado: $PRIVATE_SG_ID"
echo "========================================"
