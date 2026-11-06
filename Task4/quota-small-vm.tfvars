# ---------------------------------------------------------------------------
# Вариант под малые квоты на vCPU и память: каждая ВМ 2 vCPU, 2 ГБ, доля 20%.
# Диски и зоны как в quota-20gb-3zones.tfvars (HDD, не больше 20 ГБ на зону).
# Запуск: terraform apply -var-file="quota-20gb-3zones.tfvars" -var-file="quota-small-vm.tfvars"
# Этот файл указывается ВТОРЫМ: он переопределяет только vms.
# ---------------------------------------------------------------------------

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
    cores           = 2
    memory          = 2
    core_fraction   = 20
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
    cores           = 2
    memory          = 2
    core_fraction   = 20
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
    cores           = 2
    memory          = 2
    core_fraction   = 20
    boot_disk_size  = 8
    boot_disk_type  = "network-hdd"
    public_ip       = true
    security_groups = ["portal", "internal"]
    data_disks = {
      bi-data = { size = 4, type = "network-hdd" }
    }
  }
}
