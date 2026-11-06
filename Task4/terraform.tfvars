# ---------------------------------------------------------------------------
# Значения переменных для пилотной среды «Будущее 2.0».
# Секретов здесь нет. Ключ сервисного аккаунта передаётся через окружение:
#   export YC_SERVICE_ACCOUNT_KEY_FILE=/путь/к/key.json   (или export YC_TOKEN=...)
#
# ПЕРЕД ЗАПУСКОМ ЗАМЕНИТЕ значения, помеченные «ЗАМЕНИТЬ».
# ---------------------------------------------------------------------------

cloud_id  = "b1ghltmjbh9nkgfsdvu3"
folder_id = "b1gsmlbg49pt26ms0bc3"

default_zone = "ru-central1-a"
project_name = "future20"
environment  = "pilot"

labels = {
  owner = "data-platform-team"
}

# Адреса, которым разрешены SSH на бастион и HTTPS к порталу.
# Значения из документационных диапазонов (RFC 5737), ЗАМЕНИТЬ на реальные адреса офиса или VPN.
admin_cidr_blocks    = ["203.0.113.10/32"]
portal_allowed_cidrs = ["198.51.100.0/24"]

# Публичная часть SSH-ключа (создаётся вручную: ssh-keygen -t ed25519)
ssh_user            = "ubuntu"
ssh_public_key_path = "~/.ssh/id_ed25519.pub"

# Образ и платформа
image_family = "ubuntu-2204-lts"
platform_id  = "standard-v3"

# Пилот и учебный стенд: прерываемые ВМ дешевле. Для промышленной среды поставить false.
preemptible = true

# Сеть: одна публичная подсеть и две приватные; приватные выходят в интернет через NAT-шлюз
subnets = {
  public = { zone = "ru-central1-a", cidr = "10.10.1.0/24", private = false }
  app    = { zone = "ru-central1-a", cidr = "10.10.2.0/24", private = true }
  data   = { zone = "ru-central1-b", cidr = "10.10.3.0/24", private = true }
}

# Виртуальные машины
vms = {
  # Единственная точка входа для администраторов
  bastion = {
    role            = "Бастион для администрирования"
    subnet          = "public"
    cores           = 2
    memory          = 2
    core_fraction   = 20
    boot_disk_size  = 10
    boot_disk_type  = "network-hdd"
    public_ip       = true
    security_groups = ["bastion"]
    data_disks      = {}
  }

  # Домен «Интеграция и безопасность»: Kafka, API Gateway
  integration = {
    role            = "Шина событий и API Gateway"
    subnet          = "app"
    cores           = 4
    memory          = 8
    core_fraction   = 100
    boot_disk_size  = 20
    boot_disk_type  = "network-ssd"
    public_ip       = false
    security_groups = ["internal"]
    data_disks = {
      kafka = { size = 30, type = "network-ssd" }
    }
  }

  # Домен «Платформа данных»: загрузка, трансформации, ClickHouse
  data-platform = {
    role            = "Загрузка, трансформации и витрины"
    subnet          = "data"
    cores           = 8
    memory          = 32
    core_fraction   = 100
    boot_disk_size  = 20
    boot_disk_type  = "network-ssd"
    public_ip       = false
    security_groups = ["internal"]
    data_disks = {
      clickhouse = { size = 50, type = "network-ssd" }
      lake       = { size = 200, type = "network-hdd" }
    }
  }

  # Портал самообслуживания и BI
  portal = {
    role            = "Портал самообслуживания и BI"
    subnet          = "public"
    cores           = 4
    memory          = 8
    core_fraction   = 100
    boot_disk_size  = 20
    boot_disk_type  = "network-ssd"
    public_ip       = true
    security_groups = ["portal", "internal"]
    data_disks = {
      bi-data = { size = 20, type = "network-ssd" }
    }
  }
}

# Ночные снимки дисков данных, хранить 5 последних
backup_cron           = "0 2 * * *"
backup_snapshot_count = 5
