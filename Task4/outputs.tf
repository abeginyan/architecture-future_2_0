# ---------------------------------------------------------------------------
# Ключевые параметры созданной инфраструктуры
# ---------------------------------------------------------------------------

output "network_id" {
  description = "Идентификатор VPC-сети"
  value       = yandex_vpc_network.main.id
}

output "subnet_ids" {
  description = "Идентификаторы подсетей по именам"
  value       = { for k, s in yandex_vpc_subnet.main : k => s.id }
}

output "nat_gateway_id" {
  description = "Идентификатор NAT-шлюза для исходящего трафика приватных подсетей"
  value       = yandex_vpc_gateway.nat.id
}

output "security_group_ids" {
  description = "Идентификаторы групп безопасности"
  value       = local.security_group_ids
}

output "vm_ids" {
  description = "Идентификаторы виртуальных машин"
  value       = { for k, v in yandex_compute_instance.vm : k => v.id }
}

output "vm_private_ips" {
  description = "Внутренние адреса виртуальных машин"
  value       = { for k, v in yandex_compute_instance.vm : k => v.network_interface[0].ip_address }
}

output "vm_public_ips" {
  description = "Публичные адреса (только у ВМ с public_ip = true)"
  value       = { for k, a in yandex_vpc_address.public : k => a.external_ipv4_address[0].address }
}

output "bastion_ssh_command" {
  description = "Команда подключения к бастиону"
  value       = try("ssh ${var.ssh_user}@${yandex_vpc_address.public["bastion"].external_ipv4_address[0].address}", null)
}

output "data_disks" {
  description = "Диски данных: идентификатор, размер (ГБ) и тип"
  value = {
    for k, d in yandex_compute_disk.data : k => {
      id   = d.id
      size = d.size
      type = d.type
    }
  }
}

output "backup_schedule_id" {
  description = "Идентификатор расписания снимков дисков данных"
  value       = try(yandex_compute_snapshot_schedule.data[0].id, null)
}
