# OpenStack AIO on Dell R620

Full OpenStack AIO (not DevStack) deployed on Dell R620 with automation scripts.

## Stack
- OpenStack (Nova, Neutron, Keystone, Glance)
- Ubuntu 22.04 / 24.04
- Kubernetes on top of OpenStack

## What I built
- Automated node preparation
- Networking setup
- Deployment workflows
- Debug + teardown process

## Challenges
- Neutron networking issues (bridges, IP conflicts)
- Keystone dependency failures
- Resource constraints
- Multiple redeploy cycles

## Results
- Stable hypervisor
- Working flavors
- Running instances (K8s nodes)

## Repo structure
