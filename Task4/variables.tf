# ---------------------------------------------------------------------------
# Входные переменные. Значения задаются в terraform.tfvars.
# Секреты (ключ сервисного аккаунта, токены) в переменных и в репозитории
# не хранятся: путь к ключу передаётся отдельно, токен берётся из окружения.
# ---------------------------------------------------------------------------

# ----- Доступ к облаку -----

variable "cloud_id" {
  description = "Идентификатор облака Yandex Cloud"
  type        = string
}

variable "folder_id" {
  description = "Идентификатор каталога, в котором создаются ресурсы"
  type        = string
}

variable "default_zone" {
  description = "Зона доступности по умолчанию для провайдера"
  type        = string
  default     = "ru-central1-a"
}

variable "service_account_key_file" {
  description = "Путь к файлу авторизованного ключа сервисного аккаунта. Если null, провайдер возьмёт токен из окружения (YC_TOKEN)"
  type        = string
  default     = null
}

# ----- Общие параметры -----

variable "project_name" {
  description = "Короткое имя проекта: префикс имён ресурсов"
  type        = string
  default     = "future20"
}

variable "environment" {
  description = "Имя среды (pilot, test, prod): префикс имён и метка ресурсов"
  type        = string
  default     = "pilot"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,12}$", var.environment))
    error_message = "environment: от 2 до 12 символов, строчные латинские буквы, цифры и дефис."
  }
}

variable "labels" {
  description = "Дополнительные метки для всех ресурсов (владелец, центр затрат и т. д.)"
  type        = map(string)
  default     = {}
}

# ----- Сеть -----

variable "subnets" {
  description = <<-EOT
    Подсети сети. Ключ — имя подсети.
    private = true: подсеть без публичных адресов, выход в интернет через NAT-шлюз.
    private = false: подсеть, где отдельные ВМ получают публичный адрес (one-to-one NAT).
  EOT
  type = map(object({
    zone    = string
    cidr    = string
    private = bool
  }))

  validation {
    condition     = alltrue([for s in values(var.subnets) : can(cidrnetmask(s.cidr))])
    error_message = "Каждая подсеть должна иметь корректный CIDR, например 10.10.1.0/24."
  }
}

variable "admin_cidr_blocks" {
  description = "Адреса, с которых разрешён SSH на бастион (например, офисный адрес в виде x.x.x.x/32)"
  type        = list(string)

  validation {
    condition     = length(var.admin_cidr_blocks) > 0 && !contains(var.admin_cidr_blocks, "0.0.0.0/0")
    error_message = "Список адресов администрирования не должен быть пустым и не должен открывать SSH всему интернету (0.0.0.0/0)."
  }
}

variable "portal_allowed_cidrs" {
  description = "Адреса, которым разрешён HTTPS (443) к порталу самообслуживания"
  type        = list(string)
}

# ----- Виртуальные машины -----

variable "platform_id" {
  description = "Платформа процессоров для ВМ"
  type        = string
  default     = "standard-v3"
}

variable "image_family" {
  description = "Семейство образа ОС из публичных образов Yandex Cloud"
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "ssh_user" {
  description = "Имя пользователя ОС, которому добавляется публичный SSH-ключ"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Путь к публичному SSH-ключу (сам ключ создаётся вручную, приватная часть остаётся у администратора)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "preemptible" {
  description = "Прерываемые ВМ (дешевле, но останавливаются не позднее чем через 24 часа). Для пилота и тестов true, для промышленной среды false"
  type        = bool
  default     = false
}

variable "vms" {
  description = <<-EOT
    Описание виртуальных машин. Ключ — короткое имя ВМ.
    subnet: ключ подсети из var.subnets; security_groups: bastion, internal и/или portal;
    public_ip: выдать ВМ статический публичный адрес (one-to-one NAT);
    data_disks: дополнительные диски (ключ — имя диска).
  EOT
  type = map(object({
    role            = string
    subnet          = string
    cores           = number
    memory          = number
    core_fraction   = number
    boot_disk_size  = number
    boot_disk_type  = string
    public_ip       = bool
    security_groups = list(string)
    data_disks = map(object({
      size = number
      type = string
    }))
  }))

  validation {
    condition     = alltrue([for v in values(var.vms) : v.cores % 2 == 0 && contains([20, 50, 100], v.core_fraction)])
    error_message = "У каждой ВМ число ядер должно быть чётным, а гарантированная доля vCPU (core_fraction) равна 20, 50 или 100."
  }

  validation {
    condition = alltrue(flatten([
      for v in values(var.vms) : concat(
        [contains(["network-hdd", "network-ssd"], v.boot_disk_type)],
        [for d in values(v.data_disks) : contains(["network-hdd", "network-ssd"], d.type)]
      )
    ]))
    error_message = "Тип диска: network-hdd или network-ssd."
  }

  validation {
    condition     = alltrue([for v in values(var.vms) : alltrue([for sg in v.security_groups : contains(["bastion", "internal", "portal"], sg)])])
    error_message = "security_groups может содержать только bastion, internal и portal."
  }
}

# ----- Резервное копирование -----

variable "backup_cron" {
  description = "Расписание снимков дисков данных в формате cron (по умолчанию каждую ночь в 02:00 UTC)"
  type        = string
  default     = "0 2 * * *"
}

variable "backup_snapshot_count" {
  description = "Сколько последних снимков каждого диска хранить (квота по умолчанию: 32 снимка на облако)"
  type        = number
  default     = 5
}
