#!/bin/bash

#===============================
# Author --> Santiago Montenegro
#===============================

# Configuración
REGION="us-east-1"
VPC_NAME="proof-vpc-infra"
PUBLIC_SUBNET_NAME="proof-subnet-public"
PRIVATE_SUBNET_NAME="proof-subnet-private"
KEY_PAIR_NAME="vockey"
INSTANCE_TYPE="t3.medium"

# Obtener IDs de recursos existentes
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text --region $REGION)
PUBLIC_SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$PUBLIC_SUBNET_NAME" --query "Subnets[0].SubnetId" --output text --region $REGION)
PRIVATE_SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$PRIVATE_SUBNET_NAME" --query "Subnets[0].SubnetId" --output text --region $REGION)
PUBLIC_SG_ID=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=proof-sg-public" --query "SecurityGroups[0].GroupId" --output text --region $REGION)
PRIVATE_SG_ID=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=proof-sg-private" --query "SecurityGroups[0].GroupId" --output text --region $REGION)

# Obtener AMIs más recientes
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

# Crear instancias
echo "Creando instancias EC2..."

# 1. Windows Server en subred pública
WINDOWS_PUBLIC_ID=$(aws ec2 run-instances \
    --image-id $WINDOWS_AMI \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_PAIR_NAME \
    --subnet-id $PUBLIC_SUBNET_ID \
    --security-group-ids $PUBLIC_SG_ID \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=proof-win-public}]" \
    --query "Instances[0].InstanceId" \
    --output text \
    --region $REGION)

# 2. Ubuntu Server en subred pública
UBUNTU_PUBLIC_ID=$(aws ec2 run-instances \
    --image-id $UBUNTU_AMI \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_PAIR_NAME \
    --subnet-id $PUBLIC_SUBNET_ID \
    --security-group-ids $PUBLIC_SG_ID \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=proof-ubuntu-public}]" \
    --query "Instances[0].InstanceId" \
    --output text \
    --region $REGION)

# 3. Windows Server en subred privada
WINDOWS_PRIVATE_ID=$(aws ec2 run-instances \
    --image-id $WINDOWS_AMI \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_PAIR_NAME \
    --subnet-id $PRIVATE_SUBNET_ID \
    --security-group-ids $PRIVATE_SG_ID \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=proof-win-private}]" \
    --query "Instances[0].InstanceId" \
    --output text \
    --region $REGION)

# 4. Ubuntu Server en subred privada
UBUNTU_PRIVATE_ID=$(aws ec2 run-instances \
    --image-id $UBUNTU_AMI \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_PAIR_NAME \
    --subnet-id $PRIVATE_SUBNET_ID \
    --security-group-ids $PRIVATE_SG_ID \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=proof-ubuntu-private}]" \
    --query "Instances[0].InstanceId" \
    --output text \
    --region $REGION)

# Esperar a que las instancias estén disponibles
echo "Esperando a que las instancias estén en estado 'running'..."
aws ec2 wait instance-running \
    --instance-ids $WINDOWS_PUBLIC_ID $UBUNTU_PUBLIC_ID $WINDOWS_PRIVATE_ID $UBUNTU_PRIVATE_ID \
    --region $REGION

# Obtener información de conexión
WINDOWS_PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $WINDOWS_PUBLIC_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region $REGION)
UBUNTU_PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $UBUNTU_PUBLIC_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region $REGION)
WINDOWS_PRIVATE_IP=$(aws ec2 describe-instances --instance-ids $WINDOWS_PRIVATE_ID --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text --region $REGION)
UBUNTU_PRIVATE_IP=$(aws ec2 describe-instances --instance-ids $UBUNTU_PRIVATE_ID --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text --region $REGION)

# Mostrar resumen
echo ""
echo "========================================"
echo "Instancias creadas exitosamente"
echo "========================================"
echo ""
echo "INSTANCIAS PÚBLICAS:"
echo "1. Windows Server (RDP):"
echo "   Nombre: proof-win-public"
echo "   ID: $WINDOWS_PUBLIC_ID"
echo "   IP Pública: $WINDOWS_PUBLIC_IP"
echo "   Acceso: RDP desde cualquier lugar (puerto 3389)"
echo ""
echo "2. Ubuntu Server (SSH):"
echo "   Nombre: proof-ubuntu-public"
echo "   ID: $UBUNTU_PUBLIC_ID"
echo "   IP Pública: $UBUNTU_PUBLIC_IP"
echo "   Acceso: SSH desde cualquier lugar (puerto 22)"
echo ""
echo "INSTANCIAS PRIVADAS:"
echo "3. Windows Server (RDP):"
echo "   Nombre: proof-win-private"
echo "   ID: $WINDOWS_PRIVATE_ID"
echo "   IP Privada: $WINDOWS_PRIVATE_IP"
echo "   Acceso: RDP solo desde subred pública"
echo ""
echo "4. Ubuntu Server (SSH):"
echo "   Nombre: proof-ubuntu-private"
echo "   ID: $UBUNTU_PRIVATE_ID"
echo "   IP Privada: $UBUNTU_PRIVATE_IP"
echo "   Acceso: SSH solo desde subred pública"
echo ""
echo "========================================"
echo "Notas importantes:"
echo "- Para instancias privadas: conéctate primero a una instancia pública y luego accede via IP privada"
echo "- Para Windows: La contraseña se puede obtener con el comando:"
echo "  aws ec2 get-password-data --instance-id $WINDOWS_PUBLIC_ID --priv-launch-key $KEY_PAIR_NAME --region $REGION"
echo "========================================"
