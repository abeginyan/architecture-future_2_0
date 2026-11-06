# ---------------------------------------------------------------------------
# Вариант под квоты вашего облака: HDD по 20 ГБ в каждой из зон a, d, e
# (в зоне b квота не выделена, SSD не используем).
#   зона a: bastion (8) + integration (8) + диск kafka (4)      = 20 ГБ
#   зона d: data-platform (8) + диски clickhouse (6), lake (6)  = 20 ГБ
#   зона e: portal (8) + диск bi-data (4)                       = 12 ГБ
# Запуск: terraform apply -var-file="quota-20gb-3zones.tfvars"
# Значения заменяют subnets и vms из terraform.tfvars.
# ---------------------------------------------------------------------------

subnets = {
  public = { zone = "ru-central1-a", cidr = "10.10.1.0/24", private = false }
  app    = { zone = "ru-central1-a", cidr = "10.10.2.0/24", private = true }
  data   = { zone = "ru-central1-d", cidr = "10.10.3.0/24", private = true }
  web    = { zone = "ru-central1-e", cidr = "10.10.4.0/24", private = false }
}

vms = {
  bastion = {
    role            = "Бастион для администрирования"
    subnet          = "public"
    cores           = 2
    memory          = 2
    core_fraction   = 20
    boot_disk_size  = 8
    boot_disk_type  = "network-hdd"
    public_ip       = true
    security_groups = ["bastion"]
    data_disks      = {}
  }

  integration = {
    role            = "Шина событий и API Gateway"
    subnet          = "app"
    cores           = 4
    memory          = 8
    core_fraction   = 100
    boot_disk_size  = 8
    boot_disk_type  = "network-hdd"
    public_ip       = false
    security_groups = ["internal"]
    data_disks = {
      kafka = { size = 4, type = "network-hdd" }
    }
  }

  data-platform = {
    role            = "Загрузка, трансформации и витрины"
    subnet          = "data"
    cores           = 8
    memory          = 32
    core_fraction   = 100
    boot_disk_size  = 8
    boot_disk_type  = "network-hdd"
    public_ip       = false
    security_groups = ["internal"]
    data_disks = {
      clickhouse = { size = 6, type = "network-hdd" }
      lake       = { size = 6, type = "network-hdd" }
    }
  }

  portal = {
    role            = "Портал самообслуживания и BI"
    subnet          = "web"
    cores           = 4
    memory          = 8
    core_fraction   = 100
    boot_disk_size  = 8
    boot_disk_type  = "network-hdd"
    public_ip       = true
    security_groups = ["portal", "internal"]
    data_disks = {
      bi-data = { size = 4, type = "network-hdd" }
    }
  }
}
