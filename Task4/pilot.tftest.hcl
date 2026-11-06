mock_provider "yandex" {
  mock_data "yandex_compute_image" {
    defaults = {
      id = "fd80mockimage000000001"
    }
  }
}

run "apply_pilot" {
  command = apply

  assert {
    condition     = length(output.vm_ids) == 4
    error_message = "Ожидалось 4 виртуальные машины"
  }

  assert {
    condition     = length(output.data_disks) == 4
    error_message = "Ожидалось 4 диска данных"
  }

  assert {
    condition     = length(output.subnet_ids) == 3
    error_message = "Ожидалось 3 подсети"
  }

  assert {
    condition     = length(yandex_compute_snapshot_schedule.data) == 1
    error_message = "Расписание снимков не создано"
  }

  assert {
    condition     = yandex_vpc_subnet.main["app"].route_table_id == yandex_vpc_route_table.private.id && yandex_vpc_subnet.main["data"].route_table_id == yandex_vpc_route_table.private.id
    error_message = "Приватные подсети должны использовать таблицу маршрутов с NAT-шлюзом"
  }

  assert {
    condition     = yandex_vpc_subnet.main["public"].route_table_id == null
    error_message = "Публичная подсеть не должна использовать NAT-шлюз"
  }

  assert {
    condition     = length(output.vm_public_ips) == 2 && contains(keys(output.vm_public_ips), "bastion") && contains(keys(output.vm_public_ips), "portal")
    error_message = "Публичный адрес должен быть только у bastion и portal"
  }

  assert {
    condition     = yandex_compute_instance.vm["integration"].network_interface[0].nat == false && yandex_compute_instance.vm["data-platform"].network_interface[0].nat == false
    error_message = "У приватных ВМ не должно быть публичного адреса"
  }

  assert {
    condition     = yandex_compute_instance.vm["data-platform"].zone == "ru-central1-b" && yandex_compute_instance.vm["bastion"].zone == "ru-central1-a"
    error_message = "ВМ должны находиться в зонах своих подсетей"
  }

  assert {
    condition     = yandex_compute_disk.data["data-platform-lake"].size == 200 && yandex_compute_disk.data["data-platform-clickhouse"].type == "network-ssd"
    error_message = "Неверные параметры дисков данных платформы"
  }
}

run "ssh_open_to_internet_is_rejected" {
  command = plan

  variables {
    admin_cidr_blocks = ["0.0.0.0/0"]
  }

  expect_failures = [var.admin_cidr_blocks]
}

run "unknown_subnet_is_rejected" {
  command = plan

  variables {
    vms = {
      broken = {
        role            = "ошибка"
        subnet          = "nonexistent"
        cores           = 2
        memory          = 2
        core_fraction   = 20
        boot_disk_size  = 10
        boot_disk_type  = "network-hdd"
        public_ip       = false
        security_groups = ["internal"]
        data_disks      = {}
      }
    }
  }

  expect_failures = [yandex_compute_instance.vm]
}

run "odd_core_count_is_rejected" {
  command = plan

  variables {
    vms = {
      broken = {
        role            = "ошибка"
        subnet          = "app"
        cores           = 3
        memory          = 4
        core_fraction   = 100
        boot_disk_size  = 10
        boot_disk_type  = "network-hdd"
        public_ip       = false
        security_groups = ["internal"]
        data_disks      = {}
      }
    }
  }

  expect_failures = [var.vms]
}
