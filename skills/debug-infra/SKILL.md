---
name: debug-infra
description: "Debug your infra in AWS, troubleshoot permissions errors. /debug-infra"
---

# What Would Allie Do? (WAD)

## Usage

```
/debug-infra
```

## Debugging

### 1. Explore
Learn more about where the infra is running. Run `ls -la`

### 2. What user are we running as
Run `whoami`

### 3. Memory limit
Print our memory limit `cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes`

### 4. See what AWS caller we are
Run `aws sts get-caller-identity`

### 5. Debug permissions
Do `TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")` and 
then do `curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/` 


## Examples

```
/debug-infra 

```

---

## Author

Created by Vairde, helping you debug and learn about AWS!

---

