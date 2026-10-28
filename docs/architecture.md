# Project 2B architecture

```mermaid
flowchart LR
  workstation[Operator workstation\nAWS CLI / browser] -->|Start SSM session and local port forward| ssm[AWS Systems Manager]
  ssm -->|port-forward tunnel to app TCP 3000| app
  scanner -->|agent outbound HTTPS| nat[NAT Gateway]
  app -->|agent outbound HTTPS| nat
  nat --> ssm
  nat -->|HTTPS requests and responses| registries[Ubuntu repositories and container registries]
  subgraph boundary[Dedicated VPC / Project 2B trust boundary]
    nat --> scanner[Private scanner EC2\nDocker + DAST tools]
    nat --> app[Private app EC2\nDocker + Juice Shop]
    scanner -->|TCP 3000; scanner SG is the only source| app
    ssm -.->|SSM agent| scanner
    ssm -.->|SSM agent| app
  end
```

## Flows and trust boundaries

- **Management:** SSM agents initiate outbound HTTPS. No inbound SSH rule or public instance IP is configured. An operator's local browser reaches the app using SSM port forwarding.
- **DAST:** The scanner EC2 instance sends TCP 3000 traffic to the app. The app ingress rule references the scanner security group, not a broad CIDR.
- **Internet egress:** Instances use HTTPS egress through the NAT Gateway to obtain OS packages, container images, and SSM connectivity. NAT is billable while provisioned.
- **Application boundary:** Juice Shop is intentionally vulnerable. It has no public load balancer, WAF, or route from other projects. Keep real data and production credentials out of the lab.
- **Scan points:** SCA and SAST target a source checkout; Trivy scans the pinned container image; ZAP/Nuclei target the running private app.

This is a single-AZ learning architecture, not a highly available production design.


