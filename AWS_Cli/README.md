## Utilidad de los scripts: <br>
**·EC2.sh** <br>
<br>
*Estructura del script:* <br>
Internet <br>
│ <br>
├── VPC: "proof-vpc-infra" (CIDR: No especificado en script) <br>
│ │ <br>
│ ├── Subred Pública: "proof-subnet-public" <br>
│ │ ├── Instancia 1: "proof-win-public" (Windows Server 2022 English Full Base) <br>
│ │ │ ├─ IP Pública: Asignada <br>
│ │ │ └─ Acceso: RDP (3389) desde internet <br>
│ │ │ <br>
│ │ └── Instancia 2: "proof-ubuntu-public" (Ubuntu 22.04 Jammy Jellyfish) <br>
│ │ ├─ IP Pública: Asignada <br>
│ │ └─ Acceso: SSH (22) desde internet <br>
│ │ <br>
│ └── Subred Privada: "proof-subnet-private" <br>
│ ├── Instancia 3: "proof-win-private" (Windows Server 2022 English Full Base) <br>
│ │ ├─ IP Privada: Asignada <br>
│ │ └─ Acceso: RDP solo desde subred pública <br>
│ │ <br>
│ └── Instancia 4: "proof-ubuntu-private" (Ubuntu 22.04 Jammy Jellyfish) <br>
│ ├─ IP Privada: Asignada <br>
│ └─ Acceso: SSH solo desde subred pública <br>
│ <br>
├── Grupos de seguridad: <br>
│ ├── Public: "proof-sg-public" (Reglas: RDP/SSH abiertos a internet) <br>
│ └── Private: "proof-sg-private" (Reglas: Restringidas a VPC) <br>
│ <br>
└── Key: "vockey" (Existente, usada para todas las instancias) <br>
<br>
[ Nota: La VPC y subredes deben existir previamente (el script no las crea) ] <br>
<br>
**·VPC.sh** <br>
<br>
*Estructura del script:* <br>
Internet <br>
│ <br>
├── VPC: "proof-vpc-infra" (CIDR: 170.10.0.0/16) <br>
│ │ <br>
│ ├── Subred Pública: "proof-subnet-public" (170.10.10.0/24) <br>
│ │ ├── IGW: "proof-igw-main" (conectado a internet) <br>
│ │ └── NAT Gateway: "proof-natgw-main" (con IP elástica) <br>
│ │ <br>
│ ├── Subred Privada: "proof-subnet-private" (170.10.20.0/24) <br>
│ │ <br>
│ ├── Tabla de rutas: <br>
│ │ ├── Pública: "proof-rt-public" (0.0.0.0/0 → IGW) <br>
│ │ └── Privada: "proof-rt-private" (0.0.0.0/0 → NAT) <br>
│ │ <br>
│ └── Grupos de seguridad: <br>
│ ├── Público: "proof-sg-public" (sin reglas definidas) <br>
│ └── Privado: "proof-sg-private" (sin reglas definidas) <br>
│ <br>
[ Notas ] <br>
I. La VPC incluye soporte para IPv6 automático. <br>
II. Subred pública en ${REGION}a, privada en ${REGION}b. <br>
III. DNS y hostnames habilitados en VPC. <br>
IV. Todos los recursos tienen nombres consistentes con prefijo "proof-". <br>
V. Recordar configurar los grupos de seguridad conforme a lo que necesitemos. <br>
<br>
**·Proof.sh** <br>
<br>
*Estructura del script:* <br>
Internet <br>
│ <br>
├─ Internet Gateway <br>
│ │ <br>
│ └─ Subred Pública (10.0.1.0/24) <br>
│ ├─ Instancia LAMP (Apache + PHP + MySQL) <br>
│ └─ NAT Gateway <br>
│ │ <br>
│ └─ Subred Privada (10.0.2.0/24) [Para futuros servicios] <br>
│ <br>
└─ Security Group (SSH/HTTP/HTTPS) <br>
<br>
Archivos Generados: <br>
NombreProyecto-key.pem: Clave privada SSH (¡guárdala segura!). <br>
deployment-info-NombreProyecto.txt: Resumen de recursos y comandos útiles. <br>
<br>
**·Complete.sh** <br>
<br>
*Estructura del script:* <br>
Internet <br>
│ <br>
├── VPC: "proof-vpc-infra" (CIDR: 170.10.0.0/16) <br>
│ │ <br>
├── Internet Gateway: "proof-vpc-infra-igw" <br>
│ │ <br>
├── Subred Pública: "proof-subnet-public" (170.10.10.0/24) <br>
│ │ ├── Instancia 1: "proof-win-public" (Windows Server 2022) <br>
│ │ │ ├─ IP Pública: Asignada <br>
│ │ │ ├─ Acceso: RDP (3389) desde internet <br>
│ │ │ └─ Grupo Seguridad: proof-sg-public <br>
│ │ │ <br>
│ │ └── Instancia 2: "proof-ubuntu-public" (Ubuntu 22.04) <br>
│ │ ├─ IP Pública: Asignada <br>
│ │ ├─ Servicios: Apache+PHP, Bind9 (DNS) <br>
│ │ ├─ Acceso: SSH (22), HTTP (80), HTTPS (443), DNS (53/tcp+udp) desde internet <br>
│ │ └─ Grupo Seguridad: proof-sg-public <br>
│ │ <br>
├── NAT Gateway: "proof-natgw" (En subred pública) <br>
│ │ <br>
└── Subred Privada: "proof-subnet-private" (170.10.20.0/24) <br>
├── Instancia 3: "proof-win-private" (Windows Server 2022) <br>
│ ├─ IP Privada: Asignada <br>
│ ├─ Acceso: RDP (3389) solo desde subred pública <br>
│ └─ Grupo Seguridad: proof-sg-private <br>
│ <br>
└── Instancia 4: "proof-ubuntu-private" (Ubuntu 22.04) <br>
├─ IP Privada: Asignada <br>
├─ Acceso: SSH (22) solo desde subred pública <br>
└─ Grupo Seguridad: proof-sg-private <br>
<br>
├── Tablas de Ruta: <br>
│ ├── Pública: "proof-rt-public" (0.0.0.0/0 → IGW) <br>
│ └── Privada: "proof-rt-private" (0.0.0.0/0 → NAT Gateway) <br>
│ <br>
├── Grupos de seguridad: <br>
│ ├── Public: "proof-sg-public" <br>
│ │ ├─ Entrada: SSH(22), HTTP(80), HTTPS(443), RDP(3389), DNS(53/tcp+udp) desde 0.0.0.0/0 <br>
│ │ └─ Salida: Todo permitido <br>
│ │ <br>
│ └── Private: "proof-sg-private" <br>
│ ├─ Entrada: SSH/RDP solo desde subred pública (170.10.10.0/24) <br>
│ ├─ Entrada: Todo tráfico interno VPC (170.10.0.0/16) <br>
│ └─ Salida: Todo permitido (via NAT) <br>
│ <br>
└── Key: "vockey" (Existente, usada para todas las instancias) <br>
<br>
[ Notas técnicas ] <br>
1. La VPC SÍ es creada por el script (enable-dns-hostnames=true) <br>
2. Todas las subredes se crean en la misma AZ ([REGION]a) <br>
3. El Ubuntu público incluye: <br>
- Apache + PHP + MySQL Client+MySQL Server (info.php disponible) <br>
- Servidor Bind9 (DNS) configurado <br>
4. Conexiones recomendadas: <br>
- Windows público: RDP a IP pública <br>
- Ubuntu público: SSH/HTTP a IP pública <br>
- Instancias privadas: SSH/RDP via instancia pública <br>
