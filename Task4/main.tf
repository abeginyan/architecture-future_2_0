# ---------------------------------------------------------------------------
# «Будущее 2.0»: пилотная IaaS-инфраструктура платформы данных в Yandex Cloud.
#
# Что создаёт Terraform: сеть, подсети, NAT-шлюз и таблицу маршрутов, группы
# безопасности, статические публичные адреса, диски данных, виртуальные машины,
# расписание снимков дисков.
#
# Что делается вручную (см. diagram.png): облако и каталог, сервисный аккаунт и
# его ключ, SSH-ключи, платёжный аккаунт, бакет для удалённого состояния,
# установка и настройка ПО внутри ВМ (Kafka, ClickHouse, BI и др.).
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.130.0"
    }
  }

  # Для командной работы состояние лучше хранить в Object Storage (бакет создаётся вручную).
  # Раскомментируйте блок и заполните значения, затем выполните `terraform init -migrate-state`.
  #
  # backend "s3" {
  #   endpoints                   = { s3 = "https://storage.yandexcloud.net" }
  #   bucket                      = "future20-tfstate"
  #   region                      = "ru-central1"
  #   key                         = "pilot/terraform.tfstate"
  #   skip_region_validation      = true
  #   skip_credentials_validation = true
  #   skip_requesting_account_id  = true
  #   skip_s3_checksum            = true
  # }
}

provider "yandex" {
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = var.default_zone
  service_account_key_file = var.service_account_key_file
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  labels = merge(
    {
      project     = var.project_name
      environment = var.environment
      managed_by  = "terraform"
    },
    var.labels
  )

  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  # Плоский список дисков данных всех ВМ: ключ "<вм>-<диск>"
  vm_data_disks = merge([
    for vm_key, vm in var.vms : {
      for disk_key, disk in vm.data_disks : "${vm_key}-${disk_key}" => {
        vm   = vm_key
        zone = var.subnets[vm.subnet].zone
        size = disk.size
        type = disk.type
      }
    }
  ]...)

  # ВМ, которым нужен публичный адрес
  public_vms = { for k, v in var.vms : k => v if v.public_ip }

  security_group_ids = {
    bastion  = yandex_vpc_security_group.bastion.id
    internal = yandex_vpc_security_group.internal.id
    portal   = yandex_vpc_security_group.portal.id
  }
}

# ---------------------------------------------------------------------------
# Образ ОС
# ---------------------------------------------------------------------------

data "yandex_compute_image" "base" {
  family = var.image_family
}

# ---------------------------------------------------------------------------
# Сеть: VPC, NAT-шлюз для исходящего трафика, подсети
# ---------------------------------------------------------------------------

resource "yandex_vpc_network" "main" {
  name   = "${local.name_prefix}-net"
  labels = local.labels
}

# Общий NAT-шлюз: даёт приватным ВМ выход в интернет (обновления, репозитории пакетов)
# без публичных адресов и без входящих соединений снаружи.
resource "yandex_vpc_gateway" "nat" {
  name   = "${local.name_prefix}-nat"
  labels = local.labels

  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private" {
  name       = "${local.name_prefix}-private-rt"
  network_id = yandex_vpc_network.main.id
  labels     = local.labels

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat.id
  }
}

resource "yandex_vpc_subnet" "main" {
  for_each = var.subnets

  name           = "${local.name_prefix}-${each.key}"
  zone           = each.value.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [each.value.cidr]
  labels         = local.labels

  # Таблица маршрутов с NAT-шлюзом привязывается только к приватным подсетям
  route_table_id = each.value.private ? yandex_vpc_route_table.private.id : null
}

# ---------------------------------------------------------------------------
# Группы безопасности
# ---------------------------------------------------------------------------

# Бастион: SSH только с адресов администраторов
resource "yandex_vpc_security_group" "bastion" {
  name       = "${local.name_prefix}-bastion-sg"
  network_id = yandex_vpc_network.main.id
  labels     = local.labels

  ingress {
    description    = "SSH с адресов администраторов"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = var.admin_cidr_blocks
  }

  egress {
    description    = "Исходящий трафик"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Внутренняя группа: ВМ общаются друг с другом, SSH только с бастиона
resource "yandex_vpc_security_group" "internal" {
  name       = "${local.name_prefix}-internal-sg"
  network_id = yandex_vpc_network.main.id
  labels     = local.labels

  ingress {
    description       = "Трафик между ВМ этой группы"
    protocol          = "ANY"
    from_port         = 0
    to_port           = 65535
    predefined_target = "self_security_group"
  }

  ingress {
    description       = "SSH с бастиона"
    protocol          = "TCP"
    port              = 22
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  egress {
    description    = "Исходящий трафик (в интернет через NAT-шлюз)"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Портал самообслуживания: HTTPS только с разрешённых адресов
resource "yandex_vpc_security_group" "portal" {
  name       = "${local.name_prefix}-portal-sg"
  network_id = yandex_vpc_network.main.id
  labels     = local.labels

  ingress {
    description    = "HTTPS к порталу"
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = var.portal_allowed_cidrs
  }
}

# ---------------------------------------------------------------------------
# Статические публичные адреса (только для ВМ с public_ip = true)
# ---------------------------------------------------------------------------

resource "yandex_vpc_address" "public" {
  for_each = local.public_vms

  name   = "${local.name_prefix}-${each.key}-ip"
  labels = local.labels

  external_ipv4_address {
    zone_id = var.subnets[each.value.subnet].zone
  }
}

# ---------------------------------------------------------------------------
# Диски данных (отдельные ресурсы: живут дольше ВМ и подключаются к ней)
# ---------------------------------------------------------------------------

resource "yandex_compute_disk" "data" {
  for_each = local.vm_data_disks

  name   = "${local.name_prefix}-${each.key}"
  zone   = each.value.zone
  size   = each.value.size
  type   = each.value.type
  labels = merge(local.labels, { vm = each.value.vm })
}

# ---------------------------------------------------------------------------
# Виртуальные машины
# ---------------------------------------------------------------------------

resource "yandex_compute_instance" "vm" {
  for_each = var.vms

  name                      = "${local.name_prefix}-${each.key}"
  hostname                  = each.key
  platform_id               = var.platform_id
  zone                      = var.subnets[each.value.subnet].zone
  allow_stopping_for_update = true
  labels                    = merge(local.labels, { role = each.key })

  resources {
    cores         = each.value.cores
    memory        = each.value.memory
    core_fraction = each.value.core_fraction
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.base.id
      size     = each.value.boot_disk_size
      type     = each.value.boot_disk_type
    }
  }

  dynamic "secondary_disk" {
    for_each = each.value.data_disks

    content {
      disk_id     = yandex_compute_disk.data["${each.key}-${secondary_disk.key}"].id
      device_name = secondary_disk.key
      auto_delete = false
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.main[each.value.subnet].id
    nat                = each.value.public_ip
    nat_ip_address     = each.value.public_ip ? yandex_vpc_address.public[each.key].external_ipv4_address[0].address : null
    security_group_ids = [for sg in each.value.security_groups : local.security_group_ids[sg]]
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${local.ssh_public_key}"
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

  lifecycle {
    precondition {
      condition     = contains(keys(var.subnets), each.value.subnet)
      error_message = "ВМ ${each.key}: подсеть «${each.value.subnet}» не описана в переменной subnets."
    }
  }
}

# ---------------------------------------------------------------------------
# Резервное копирование: ночные снимки всех дисков данных
# ---------------------------------------------------------------------------

resource "yandex_compute_snapshot_schedule" "data" {
  count = length(local.vm_data_disks) > 0 ? 1 : 0

  name   = "${local.name_prefix}-data-backup"
  labels = local.labels

  schedule_policy {
    expression = var.backup_cron
  }

  snapshot_count = var.backup_snapshot_count

  snapshot_spec {
    description = "Автоматический снимок диска данных (${local.name_prefix})"
    labels      = local.labels
  }

  disk_ids = [for d in yandex_compute_disk.data : d.id]
}
