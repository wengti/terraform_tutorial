# Terraform Learning Notes

Personal recap of what I've learned so far, using the web server setup in
[`2-practice/main.tf`](2-practice/main.tf) as the working example.

---

## 1. Resources Used to Create an EC2 Instance

To get a single EC2 instance publicly reachable over HTTP/HTTPS/SSH, all of the
following resources are needed. They don't just sit side by side — each one
plugs into the next.

| # | Resource | Role in one line |
|---|----------|-------------------|
| 1 | **VPC** | Your own private, isolated network in AWS — the address space everything else lives inside. |
| 2 | **Subnet** | A slice of the VPC pinned to one Availability Zone; the actual pool of IPs your instance draws from. |
| 3 | **Internet Gateway** | The door between your VPC and the public internet — without it, nothing in the VPC can reach out or be reached. |
| 4 | **Route Table** | The "map" that says where traffic goes; the route sends internet-bound traffic to the gateway. |
| 5 | **Route Table Association** | Attaches that map to your subnet — this is what makes the subnet public. Without it the routes wouldn't apply. |
| 6 | **Security Group** | A virtual firewall around the instance; ingress rules open ports 80/443 (web) and 22 (SSH), egress allows all out. |
| 7 | **Network Interface / ENI** | The virtual "network card" that plugs the instance into the subnet — holds its private IP and the security group. |
| 8 | **Elastic IP** | A fixed public IP address attached to the ENI, giving the instance a stable internet-facing address (survives stop/start). |
| 9 | **EC2 Instance** | The actual virtual server — the compute that boots Ubuntu, runs setup, and serves the web page. |

### Request flow (visitor hits `http://<Elastic IP>`)

```
Visitor types  http://<Elastic IP>
   |
① Elastic IP        → routes the request to the building's public address
② Internet Gateway   → the request enters the VPC through the front door
③ Route Table        → signage says "this belongs to the 10.0.1.0/24 floor" → sends it there
④ (Association)      → is why the subnet knew to follow that signage at all
⑤ Subnet             → request arrives on the correct floor
⑥ Security Group     → guard checks: port 80? allowed ✅ (SSH from a stranger would be ❌)
⑦ Network Interface  → delivers the packet to jack 10.0.1.50
⑧ EC2 Instance       → Apache answers, builds the page
   |
   └── reply retraces the path back out ⑦→⑥→⑤→③→② → Elastic IP → visitor
```

---

## 2. Finding the Documentation for a Resource

The fastest way to find the docs for any resource is to search:

```
terraform aws <resource>
```

For example:
- Want the subnet docs? Search **"terraform aws subnet"**.
- Want the EC2 instance docs? Search **"terraform aws instance"**.
- Want the elastic IP docs? Search **"terraform aws eip"**.

This reliably lands on the [Terraform AWS Provider registry page](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
for that resource, which lists all available arguments, attributes, and — importantly —
any implicit relationships (like the fact that `aws_eip` references a network interface).

---

## 3. Security Group — Ingress vs Egress

The security group (`aws_security_group.allow_web`) is the firewall around the instance.
In the newer AWS provider, ingress/egress rules are their own resources
(`aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule`)
rather than inline blocks.

**Ingress (incoming traffic) — restricted per port:**
- **HTTPS (443)** and **HTTP (80)** — open to anyone (`0.0.0.0/0` and `::/0`), since this is a public web server.
- **SSH (22)** — locked down to a single IP: my own device's public IP, hardcoded for now.

```hcl
resource "aws_vpc_security_group_ingress_rule" "allow_web_ipv4" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "211.24.221.117/32" # Only this IP address can access SSH
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}
```

**Egress (outgoing traffic) — no limit set:**
The instance is allowed to reach anywhere on any port/protocol (`ip_protocol = "-1"` means "all").
Useful since the instance needs to reach out for things like `apt update`.

```hcl
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}
```

> **Takeaway:** ingress should be as narrow as possible (why SSH is IP-locked), while egress
> is commonly left open unless there's a specific reason to restrict outbound traffic.

---

## 4. The `depends_on` Attribute

Terraform normally figures out resource ordering on its own — if resource B references
`resource_a.id`, Terraform already knows to create A before B. Most of the time you never
need to think about ordering explicitly.

There are rare cases, though, where a dependency exists but isn't visible through a direct
attribute reference in the code. In this project, that shows up twice:

- **Elastic IP → Internet Gateway** — per the `aws_eip` documentation, the EIP needs the
  gateway to exist first (so the IP can actually be routable), even though the Terraform
  code for the EIP doesn't reference the gateway directly.
- **EC2 Instance → Elastic IP** — the instance is set up to depend on the EIP being ready
  before it boots.

That's exactly when `depends_on` comes in — to force an explicit ordering Terraform
wouldn't infer on its own:

```hcl
resource "aws_eip" "one" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web_server_nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [ aws_internet_gateway.gw ]
}

resource "aws_instance" "prod_instance" {
  # ...
  depends_on = [ aws_eip.one ]
}
```

---

## 5. General Commands to Run a Terraform Project

```bash
terraform init      # download providers, set up the working directory
terraform plan       # preview what will change
terraform apply       # actually create/update the infrastructure
terraform destroy      # tear everything down
```

### Useful flags

**`-auto-approve`** — skip the interactive "yes" confirmation prompt:
```bash
terraform apply -auto-approve
terraform destroy -auto-approve
```

**`-target`** — only create/destroy a specific resource, instead of the whole project:
```bash
terraform apply -target aws_instance.prod_instance
terraform destroy -target aws_instance.prod_instance
```

**`-var-file`** — point Terraform at a specific `.tfvars` file instead of the default
`terraform.tfvars` (see [Variables](#8-variables) below):
```bash
terraform apply -var-file example.tfvars
```

---

## 6. EC2 Instance — Assigning an SSH Key

1. Create a key pair in AWS first (via console or `aws_key_pair` resource) — this
   gives it a name registered in AWS.
2. Reference that name in the instance's `key_name` argument:

```hcl
resource "aws_instance" "prod_instance" {
  ami           = "ami-0b6d9d3d33ba97d99"
  instance_type = "t3.micro"
  key_name      = "terraform_access_key"
  # ...
}
```

Without this, there's no way to SSH into the instance after it's launched.

---

## 7. Output

Outputs surface a resource's attribute after `apply` finishes — handy for values
like a public IP that you'd otherwise have to go look up in the console.

```hcl
output "server_public_ip" {
    value = aws_eip.one.public_ip
} # This value will be displayed when run terraform output
```

To view it later without re-running `apply`:
```bash
terraform output
```

---

## 8. Variables

Variables let you parameterize a config instead of hardcoding values. Terraform
resolves a variable's value in this order:
1. Look for `terraform.tfvars` (or whatever file is passed via `-var-file`) and use the value there.
2. If not found, prompt the user to enter a value at `terraform apply`.
3. If still not set, fall back to the `default` listed in the variable block.

```hcl
variable "subnet_prefix" {
    description = "A list of variables used to setup the multiple subnet"
    # default
    # type
} # terraform will first look for terraform.tfvars to fill in the value.
# Else, it will prompt the user to enter a value on `terraform apply`
# Else, it will use the default value listed
# You can use terraform apply -var-file example.tfvars so you can save variables in a different file name
```

Variables can be a **string**, a **list**, or a **list of objects**. Lists are
zero-indexed (`var.my_list[0]` is the first element).

**String:**
```hcl
variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}
```

**List:**
```hcl
variable "availability_zones" {
  description = "AZs to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}
```

**List of objects** (used for `subnet_prefix` in this project):
```hcl
variable "subnet_prefix" {
  description = "A list of variables used to setup the multiple subnet"
  type = list(object({
    cidr_block = string
    name       = string
  }))
}
```

`terraform.tfvars`:
```hcl
subnet_prefix = [
    {
        cidr_block = "10.0.1.0/24",
        name = "Production Subnet 1"
    },
    {
        cidr_block = "10.0.2.0/24",
        name = "Development Subnet 1"
    }
]
```

Used in the resource with index access (`[0]` = first entry, `[1]` = second entry):
```hcl
resource "aws_subnet" "prod_subnet_1" {
  vpc_id            = aws_vpc.prod_vpc.id
  cidr_block        = var.subnet_prefix[0].cidr_block
  availability_zone = "us-east-1a"

  tags = {
    Name = var.subnet_prefix[0].name
  }
}
```

---

## 9. Extra Useful Commands

```bash
terraform state list          # list every resource Terraform is tracking, by address
terraform state show <addr>   # show all attributes/values of one specific resource
```

- **`state list`** — gives you the exact resource address (e.g. `aws_instance.prod_instance`),
  which is what you need for flags like `-target` in `apply`/`destroy`.
- **`state show`** — useful for discovering what attributes a resource actually has, so you
  know what's available to reference in an `output` block.

---

## 10. `user_data` in EC2 Instance

```hcl
user_data = <<-EOF
            #!/bin/bash
            sudo apt update -y
            sudo apt install apache2 -y
            sudo systemctl start apache2
            sudo bash -c 'echo your very first web server > /var/www/html/index.html'
            EOF
```

- `user_data` only runs **once**, at first boot / initialization. It's not re-run on
  every `apply` or on instance restart.
- Because of that, it's best treated as bootstrap-only (installing a base package, initial
  config) rather than for anything that needs to change over the instance's life. For
  ongoing setup or changes after launch, it's better to SSH in and do it manually (or move
  to a proper config-management tool if it grows beyond a few commands).
