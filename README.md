# 🔐 Secure Multi-Tenant AWS Platform

> Infrastructure AWS **multi-clients, cloisonnée et entièrement automatisée** :
> une zone bastion centrale (proxy sortant filtrant, reverse proxy, VPN
> d'administration) et N zones clientes **isolées** entre elles, reliées par
> **VPC peering**. Tout est décrit en **Infrastructure-as-Code** — Terraform
> pour le réseau & AWS, Ansible pour la configuration des services.


**Stack :** AWS · Terraform · Ansible · OpenVPN (PKI easy-rsa) · Squid · Nginx · KMS · CloudTrail · AWS Config · AWS Backup

---

## 📑 Sommaire

1. [Vue d'ensemble](#1-vue-densemble)
2. [Architecture](#2-architecture)
3. [Plan d'adressage](#3-plan-dadressage)
4. [Matrice de flux](#4-matrice-de-flux)
5. [Les composants en détail](#5-les-composants-en-détail)
6. [Déploiement & reproduction](#6-déploiement--reproduction)
7. [Problèmes rencontrés & solutions](#7-problèmes-rencontrés--solutions)
8. [État d'avancement](#8-état-davancement)
9. [Structure du dépôt](#9-structure-du-dépôt)

---

## 1. Vue d'ensemble

L'objectif est d'héberger plusieurs clients web sur AWS de manière **sécurisée et
industrialisée**, en respectant des contraintes fortes :

- L'**administration** n'est accessible **que via un VPN dédié** (machine d'admin sans IP publique).
- Les **VPC clients n'ont aucune Internet Gateway** : tout flux entrant passe par un **reverse proxy**, tout flux sortant par un **proxy filtrant**.
- Les **zones clientes sont étanches** entre elles.
- La plateforme AWS elle-même est durcie (chiffrement, audit, sauvegardes, conformité).

Trois clients réels sont déployés à titre de démonstration : **cybersky**, **drox360** et **visuance** (applications Vite/React).

---

## 2. Architecture

![Architecture Landing Zone](screenshots/00-architecture-landing-zone.png)

*Schéma d'architecture et zone de landing centralisée pour les services AWS, le VPN, le reverse proxy et les VPC clients.*

---

## 3. Plan d'adressage

Convention scalable : `10.<index>.0.0/16` par VPC → ajouter un client = incrémenter l'index.

| Zone | VPC CIDR | Subnets |
|------|----------|---------|
| **Bastion** | `10.0.0.0/16` | `10.0.1.0/24` DMZ public · `10.0.2.0/24` VPN public · `10.0.10.0/24` admin privé |
| **cybersky** | `10.1.0.0/16` | `10.1.1.0/24` web privé · `10.1.2.0/24` data privé |
| **drox360** | `10.2.0.0/16` | `10.2.1.0/24` web privé · `10.2.2.0/24` data privé |
| **visuance** | `10.3.0.0/16` | `10.3.1.0/24` web privé · `10.3.2.0/24` data privé |
| Tunnel VPN | `10.5.0.0/24` | réseau interne poussé aux administrateurs |

---

## 4. Matrice de flux

Politique **« deny par défaut »** : chaque Security Group n'autorise que le strict nécessaire.

| # | Source | Destination | Port / Proto | Justification |
|---|--------|-------------|--------------|---------------|
| 1 | Internet | Serveur VPN | UDP 1194 | Seul point d'entrée d'administration |
| 2 | Internet | Reverse Proxy | TCP 443 / 80 | Seul point d'entrée applicatif |
| 3 | Tunnel VPN `10.5.0.0/24` | Bastion | TCP 22 | Admin **uniquement** via VPN |
| 4 | Bastion / Ansible | Web, Proxy, RP, VPN | TCP 22 | Administration & déploiement |
| 5 | Reverse Proxy | Serveurs web clients | TCP 80 | Trafic entrant (via peering, par FQDN) |
| 6 | Serveurs web clients | Squid | TCP 3128 | **Seule** sortie (dépôts de paquets) |
| 7 | Web client | RDS (intra-VPC) / S3 (endpoint) | — | Données |
| 8 | Client ↔ Client | — | **DENY** | Étanchéité (pas de peering croisé) |

---

## 5. Les composants en détail

### 5.1 Le réseau bastion

VPC `10.0.0.0/16` découpé en 3 subnets. La distinction **public / privé** ne se fait pas par une option, mais par le **routage** : un subnet est public uniquement si sa table de routage a une route `0.0.0.0/0 → Internet Gateway`. Le subnet admin n'a, lui, **aucune** route vers Internet — d'où son isolement.

![VPC bastion](screenshots/02-vpc-bastion-console.png)
*Le VPC bastion `10.0.0.0/16`*

![Subnets bastion](screenshots/03-subnets-bastion-console.png)
*Les 3 subnets (DMZ, VPN, admin)*

![Routage bastion](screenshots/04-routage-bastion-console.png)
*Tables de routage (route IGW sur la publique)*

![Instances bastion](screenshots/06-instances-bastion-console.png)
*Les 4 instances (le bastion sans IP publique)*

### 5.2 Le serveur VPN + PKI

OpenVPN auto-hébergé sur une instance EC2 dans un subnet dédié. L'authentification se fait par **certificats** issus d'une **PKI** (easy-rsa) : une autorité racine (CA) signe le certificat du serveur et un certificat par administrateur. Le serveur fait du **NAT** pour que les admins atteignent le bastion privé à travers le tunnel.

![Instance OpenVPN](screenshots/05-instance-openvpn-console.png)
*L'instance OpenVPN en fonctionnement*

![Connexion VPN réussie](screenshots/08-vpn-connexion-reussie.png)
*`Initialization Sequence Completed` + ping du tunnel*

![SSH via VPN](screenshots/09-ssh-bastion-prive-via-vpn.png)
*SSH vers le bastion privé `10.0.10.x`, uniquement via le VPN*

### 5.3 Le proxy sortant (Squid)

Squid filtre les flux **sortants** des clients : il n'autorise que les **dépôts de paquets** (whitelist de domaines) et **uniquement depuis les réseaux clients**. C'est la double sécurité : le Security Group gère *qui* peut entrer (port 3128 depuis les VPC clients), Squid gère *vers où* on peut sortir.

![Configuration Squid](screenshots/10-squid-configure.png)
*Configuration Squid + ACL générées*

![Logs Squid](screenshots/15-squid-filtrage-log.png)
*Preuve du filtrage : logs des clients téléchargeant leurs paquets via le proxy*

### 5.4 Le reverse proxy (Nginx)

Nginx reçoit le HTTPS depuis Internet, **termine le TLS**, et relaie en HTTP vers le serveur web privé du bon client selon le **FQDN** demandé (un *vhost* par client). Les serveurs web ne sont **jamais** exposés directement.

![Reverse proxy OK](screenshots/11-reverse-proxy-ok.png)
*Reverse proxy en place (test HTTPS + redirection 301)*

![Flux complet curl](screenshots/17-flux-complet-curl.png)
*Test CLI du flux complet (curl par FQDN)*

![Site Cybersky](screenshots/18-site-cybersky-navigateur.png)
*Le site cybersky dans le navigateur*

![Site drox360](screenshots/19-site-drox360.png)
*Le site drox360*

![Site visuance](screenshots/20-site-visuance.png)
*Le site visuance*

### 5.5 Les VPC clients & le peering

Chaque client est un VPC privé **sans Internet Gateway**, relié au bastion par **VPC peering**. Point élégant : le peering **n'est pas transitif** — comme aucun peering ne relie les clients entre eux, leur **étanchéité est gratuite**, sans configuration supplémentaire.

![VPC clients créés](screenshots/12-vpc-clients-crees.png)
*Les 3 VPC clients (`10.1`, `10.2`, `10.3`)*

![Peering actif](screenshots/13-peering-actif.png)
*Les 3 connexions de peering actives*

### 5.6 Le déploiement des sites

Les sites sont des applications **Vite/React**. La bonne pratique appliquée : **builder l'artefact statique sur une machine disposant d'Internet**, puis **n'expédier que le `dist/`** (via Ansible) sur le serveur privé, qui se contente de le servir avec Nginx. Le serveur client reste minimal, sans Node ni accès npm — il installe Nginx **uniquement à travers Squid**.

![Sites déployés](screenshots/14-sites-deployes-recap.png)
*`PLAY RECAP` Ansible vert sur les 3 clients*

![Site servi localement](screenshots/16-site-servi-localement.png)
*Le HTML servi par Nginx sur le serveur privé*

### 5.7 La sécurité de la plateforme

- **KMS** : clé de chiffrement (rotation activée) pour les buckets S3 et les données.
- **CloudTrail** : journalisation multi-régions de toutes les actions API.
- **VPC Endpoint S3 + bucket chiffré par client** : les clients accèdent à S3 sans passer par Internet.
- **AWS Backup** : coffre chiffré + plan de sauvegarde quotidien des ressources taggées.
- **AWS Config** : 3 règles de conformité managées (validation automatique des règles de filtrage → **tâche 4**).

![KMS et CloudTrail](screenshots/21-kms-cloudtrail.png)
*Clé KMS + CloudTrail actif*

![Buckets S3 chiffrés](screenshots/22-buckets-s3-chiffres.png)
*Buckets S3 chiffrés SSE-KMS*

![VPC Endpoints S3](screenshots/23-vpc-endpoints-s3.png)
*Les 3 VPC Endpoints S3*

![AWS Backup](screenshots/24-aws-backup.png)
*Plan de sauvegarde AWS Backup*

![AWS Config conformité](screenshots/25-aws-config-conformite.png)
*Règles AWS Config + statut de conformité*

---

## 6. Déploiement & reproduction

**Prérequis :** AWS CLI configuré, Terraform ≥ 1.6, Ansible (sous Linux/WSL), une paire de clés EC2 `secureaws-key`.

```bash
# 1. Réseau, instances & sécurité AWS
cd terraform
terraform init
terraform apply

# 2. Configuration des services (le VPN doit être actif pour le rebond)
cd ../ansible
ansible-playbook -i inventory/hosts.ini squid.yml       # proxy filtrant
ansible-playbook -i inventory/hosts.ini revproxy.yml    # reverse proxy + vhosts
ansible-playbook -i inventory/hosts.ini webserver.yml   # déploiement des sites
```

Pour accéder aux sites par navigateur, ajouter dans le fichier `hosts` local :

```
<IP_PUBLIQUE_REVERSE_PROXY>  cybersky.secureaws.local
<IP_PUBLIQUE_REVERSE_PROXY>  drox360.secureaws.local
<IP_PUBLIQUE_REVERSE_PROXY>  visuance.secureaws.local
```

---

## 7. Problèmes rencontrés & solutions

Le projet a impliqué un vrai travail de **diagnostic réseau**. Voici les obstacles majeurs et leur résolution — la partie la plus formatrice.

### 🔴 7.1 — SSH/Ansible en timeout : route vers l'IGW manquante

**Symptôme :** impossible de joindre l'instance VPN en SSH (`Connection timed out`), alors que le Security Group et l'IP étaient corrects.

**Diagnostic (par élimination) :** test `nc github.com 22` → OK (le réseau local ne bloque pas le 22) ; `describe-security-groups` → SG correct ; `describe-instances` → instance OK ; `describe-route-tables` → **réponse vide**. Le subnet VPN n'avait **aucune table de routage explicite**, donc aucune route vers l'Internet Gateway.

**Cause :** un `timeout` (et non un `refused`) signifie que le paquet arrive mais que la **réponse ne peut pas revenir**. Le bloc de routage (IGW + tables) n'avait pas été appliqué.

**Solution :** ajout des ressources de routage (`aws_internet_gateway`, `aws_route_table`, associations) et `terraform apply`.
**Leçon :** une instance publique a besoin de **trois** choses, pas deux — IP publique **+** SG ouvert **+** route vers l'IGW.

### 🔴 7.2 — Renommage des clients : deadlock de remplacement de Security Group

**Symptôme :** lors du renommage des clients, `terraform apply` reste bloqué **13 minutes** puis échoue : `DependencyViolation: resource sg-… has a dependent object`.

**Cause :** changer le *nom* d'un SG force sa **recréation**. Par défaut, Terraform tente de **supprimer l'ancien avant de créer le nouveau** — mais l'ancien est encore attaché à l'instance → suppression impossible.

**Solution :** `lifecycle { create_before_destroy = true }` sur le SG → Terraform crée le nouveau, bascule l'instance dessus, **puis** supprime l'ancien (désormais détaché).
**Leçon :** tout SG attaché à une instance et susceptible d'être remplacé doit avoir `create_before_destroy`.

### 🔴 7.3 — `apt` des clients en échec : la longue fausse piste IPv6

**Symptôme :** les serveurs web clients ne pouvaient pas faire `apt-get update` à travers Squid (`Failed to update apt cache`).

**Fausses pistes explorées :** `security.ubuntu.com` résolvant en IPv6 et le VPC n'ayant pas d'IPv6, Squid a longtemps été soupçonné à tort (essais de `dns_v4_first`, désactivation IPv6, `tcp_outgoing_address`)… qui ont en réalité **dégradé** la situation.

**La vraie cause (7.4) :** un problème de **routage**, pas de Squid.

### 🔴 7.4 — La cause racine : route de peering manquante côté bastion

**Symptôme décisif :** `nc <squid> 3128` depuis un client → **timeout**. Le client ne pouvait même pas établir de connexion TCP vers Squid.

**Diagnostic :** la **table de routage publique du bastion** (où vit Squid) ne contenait que `local` et `0.0.0.0/0 → IGW` — **aucune route vers `10.1/10.2/10.3` via le peering**. La table du client, elle, était correcte. Résultat : le SYN du client arrivait sur Squid, mais la **réponse de Squid n'avait aucun chemin retour** → timeout unidirectionnel.

**Solution :** `terraform apply` a recréé les routes `from_bastion` manquantes dans la table publique. Côté clients, il a fallu pointer `apt` sur le **miroir régional EC2** (`eu-west-3.ec2.archive.ubuntu.com`, IPv4, joignable via Squid) pour éviter `security.ubuntu.com`.
**Leçon :** un blocage **unidirectionnel** (timeout) trahit presque toujours un **chemin retour** manquant. Toujours vérifier le routage **des deux côtés** d'un peering.

### 🟠 7.5 — Sites Vite/React, pas du HTML statique

**Constat :** les sites clients sont des apps Vite/React nécessitant un **build** (`npm run build`). Builder sur le serveur client (privé) aurait imposé d'autoriser `npmjs.org` dans Squid et d'installer Node.

**Solution :** build de l'artefact `dist/` sur une machine avec Internet, puis expédition du **statique uniquement** sur le serveur privé (séparation build/runtime).

### 🟠 7.6 — Client `10.3` bloqué par Squid (et c'était… correct)

**Symptôme :** au premier déploiement, cybersky (`10.1`) et drox360 (`10.2`) passaient, mais visuance (`10.3`) échouait.

**Cause :** le Security Group **et** la whitelist de Squid n'autorisaient que `10.1` et `10.2`. visuance (`10.3`) était donc **correctement bloqué** — la preuve que le filtrage fonctionne !

**Solution :** ajout de `10.3.0.0/16` au SG Squid et à la liste des réseaux clients.

### 🟠 7.7 — `node_modules` Windows incompatibles & `/mnt/c`

**Cause :** les dépendances installées sous Windows contiennent des binaires natifs incompatibles Linux ; et `npm` n'arrivait pas à écrire sur le montage `/mnt/c`.

**Solution :** build dans le système de fichiers **Linux natif** (`/tmp`), puis copie du seul `dist/` vers le dossier projet.

---

## 8. État d'avancement

| Objectif du projet | État |
|----------------|------|
| **1. Conception** (adressage, matrice de flux, schéma, modèle de déploiement) | ✅ |
| **2. Mise en œuvre** (réseau, services centraux, **3** clients + peering, sites) | ✅ |
| **3. Production** (déploiement client < 3 min, changements de masse) | 🔄 module prêt, script d'enrobage à finaliser |
| **4. Conformité** (validation automatique des règles) | ✅ via AWS Config (3 règles managées) |
| **5. Sécurité plateforme** (KMS, CloudTrail, S3 chiffré, AWS Backup, AWS Config) | ✅ *(RDS laissé optionnel — S3 couvre le besoin)* |

**Validé de bout en bout :** accès admin par VPN vers une machine privée · installation de paquets *uniquement* via le proxy filtrant · étanchéité inter-clients · sites servis depuis des serveurs sans IP publique.

---

## 9. Structure du dépôt

| Dossier | Rôle |
|---------|------|
| `docs/` | Schéma d'architecture (draw.io + PNG) |
| `terraform/` | Réseau & ressources AWS (bastion + module `client` + sécurité) |
| `terraform/modules/client/` | Module paramétré : un appel = un client complet |
| `ansible/` | Rôles `squid`, `nginx_revproxy`, `webserver` + inventaire |
| `screenshots/` | Captures de chaque étape |

---

*Réalisé avec Terraform & Ansible — infrastructure reproductible de A à Z.*
