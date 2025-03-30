#!/bin/bash

### 🔧 CONFIGURACIÓN ###
AWS_REGION="us-east-1"
DB_INSTANCE_IDENTIFIER="proof-mysql-private"
DB_NAME="proofdb"
DB_USERNAME="admin"
DB_PASSWORD="P@ssw0rdSecure123!"  # Cambia esto
DB_INSTANCE_CLASS="db.t3.micro"

### 🛡️ OBTENER INFRAESTRUCTURA EXISTENTE ###
echo "🔍 Obteniendo información de la infraestructura existente..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=proof-vpc-infra" --query "Vpcs[0].VpcId" --output text --region $AWS_REGION)
PRIVATE_SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=proof-subnet-private" --query "Subnets[0].SubnetId" --output text --region $AWS_REGION)
UBUNTU_PRIVATE_SG_ID=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=proof-sg-private" --query "SecurityGroups[0].GroupId" --output text --region $AWS_REGION)
UBUNTU_PRIVATE_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=proof-ubuntu-private" --query "Reservations[0].Instances[0].PrivateIpAddress" --output text --region $AWS_REGION)

### 🔄 FUNCIÓN PARA VERIFICAR ERRORES ###
check_error() {
    if [ $? -ne 0 ]; then
        echo "❌ Error en el paso anterior. Deteniendo el script."
        exit 1
    fi
}

### 1️⃣ VERIFICAR RECURSOS EXISTENTES ###
echo "🔍 Verificando recursos en AWS..."

[ -z "$VPC_ID" ] && { echo "ERROR: No se encontró la VPC 'proof-vpc-infra'"; exit 1; }
[ -z "$PRIVATE_SUBNET_ID" ] && { echo "ERROR: No se encontró la subred privada"; exit 1; }
[ -z "$UBUNTU_PRIVATE_SG_ID" ] && { echo "ERROR: No se encontró el security group privado"; exit 1; }
[ -z "$UBUNTU_PRIVATE_IP" ] && { echo "ERROR: No se encontró la instancia Ubuntu privada"; exit 1; }

### 2️⃣ OBTENER O CREAR SECURITY GROUP PARA RDS ###
echo "🛡️ Verificando Security Group para RDS..."
RDS_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=proof-rds-mysql-sg" "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[0].GroupId" \
    --output text \
    --region $AWS_REGION)

if [ -z "$RDS_SG_ID" ]; then
    echo "🛡️ Creando nuevo Security Group para RDS..."
    RDS_SG_ID=$(aws ec2 create-security-group \
        --group-name "proof-rds-mysql-sg" \
        --description "Security Group para MySQL RDS (acceso solo desde instancia Ubuntu privada)" \
        --vpc-id "$VPC_ID" \
        --region "$AWS_REGION" \
        --query "GroupId" --output text)
    check_error

    # Etiquetar el security group
    aws ec2 create-tags \
        --resources "$RDS_SG_ID" \
        --tags Key=Name,Value=proof-rds-mysql-sg \
        --region "$AWS_REGION"
else
    echo "🛡️ Usando Security Group existente: $RDS_SG_ID"
fi

### 3️⃣ CONFIGURAR REGLAS DE ACCESO ###
echo "🔐 Configurando reglas de acceso..."
# Verificar si la regla ya existe
EXISTING_RULE=$(aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=$RDS_SG_ID" "Name=referenced-group-info.group-id,Values=$UBUNTU_PRIVATE_SG_ID" "Name=ip-protocol,Values=tcp" "Name=from-port,Values=3306" \
    --query "length(SecurityGroupRules)" \
    --output text \
    --region $AWS_REGION)

if [ "$EXISTING_RULE" -eq "0" ]; then
    echo "🔐 Agregando regla de acceso..."
    aws ec2 authorize-security-group-ingress \
        --group-id "$RDS_SG_ID" \
        --protocol tcp \
        --port 3306 \
        --source-group "$UBUNTU_PRIVATE_SG_ID" \
        --region "$AWS_REGION"
    check_error
else
    echo "🔐 Regla de acceso ya existe, omitiendo creación"
fi

### 4️⃣ CREAR INSTANCIA RDS EN LA SUBNET PRIVADA ###
echo "🛢️ Creando instancia RDS MySQL en la subred privada existente..."
# Obtener la AZ de la subred privada existente
SUBNET_AZ=$(aws ec2 describe-subnets --subnet-ids "$PRIVATE_SUBNET_ID" --query "Subnets[0].AvailabilityZone" --output text --region $AWS_REGION)

# Verificar si la instancia RDS ya existe
EXISTING_DB=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
    --query "length(DBInstances)" \
    --output text \
    --region $AWS_REGION 2>/dev/null || echo "0")

if [ "$EXISTING_DB" -eq "0" ]; then
    echo "🛢️ Creando nueva instancia RDS..."
    aws rds create-db-instance \
        --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
        --allocated-storage 20 \
        --db-instance-class "$DB_INSTANCE_CLASS" \
        --engine mysql \
        --engine-version "8.0" \
        --master-username "$DB_USERNAME" \
        --master-user-password "$DB_PASSWORD" \
        --db-name "$DB_NAME" \
        --vpc-security-group-ids "$RDS_SG_ID" \
        --no-publicly-accessible \
        --availability-zone "$SUBNET_AZ" \
        --no-multi-az \
        --region "$AWS_REGION"
    check_error

    echo "⏳ Esperando a que la instancia RDS esté disponible..."
    aws rds wait db-instance-available \
        --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
        --region "$AWS_REGION"
else
    echo "🛢️ La instancia RDS ya existe, omitiendo creación"
fi

### 🎉 MOSTRAR INFORMACIÓN DE CONEXIÓN ###
RDS_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
    --query "DBInstances[0].Endpoint.Address" \
    --output text \
    --region $AWS_REGION)

PUBLIC_UBUNTU_IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=proof-ubuntu-public" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text \
    --region $AWS_REGION)

echo ""
echo "✅ Configuración completada!"
echo "🔗 Endpoint de RDS: $RDS_ENDPOINT"
echo "📌 Ubicado en la misma AZ que tu instancia Ubuntu privada ($SUBNET_AZ)"
echo "📌 Instancia Ubuntu privada IP: $UBUNTU_PRIVATE_IP"
echo ""
echo "Para conectarte:"
echo "1. Accede a tu instancia pública:"
echo "   ssh -i vockey.pem ubuntu@$PUBLIC_UBUNTU_IP"
echo "2. Desde allí, conecta a la instancia privada:"
echo "   ssh ubuntu@$UBUNTU_PRIVATE_IP"
echo "3. Instala MySQL client si es necesario:"
echo "   sudo apt update && sudo apt install mysql-client -y"
echo "4. Conéctate al RDS:"
echo "   mysql -h $RDS_ENDPOINT -u $DB_USERNAME -p"
