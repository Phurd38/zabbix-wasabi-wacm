# Supervision Wasabi avec Zabbix

Surveillance d'un parc Wasabi géré dans **WACM** (Wasabi Account Control Manager) :
tous les sous-comptes et tous leurs buckets, depuis Zabbix.

| Chemin | À quoi ça sert |
|---|---|
| `template/wasabi_wacm_connect_by_http.yaml` | Le template à importer dans Zabbix |
| `tools/Test-WacmConnectApi.ps1` | Test de la clé API (à lancer avant l'import) |
| `src/` | Sources du template et script de fabrication (voir § 4) |
| `docs/api-samples/` | Exemples de réponses de l'API, anonymisés |
| `legacy/` | Ancienne piste Stats API, pour comptes hors WACM |

> Version anglaise : [README.md](README.md)

---

## 1. Le principe en trois phrases

Wasabi publie **une fois par jour** un relevé d'utilisation par compte et par bucket.

Le template interroge la **WACM Connect API** une fois par heure : un appel pour
lister les sous-comptes, puis un appel par sous-compte pour ses buckets. Le tout
revient en un seul bloc JSON que Zabbix découpe ensuite en métriques.

La découverte est automatique : un nouveau client ou un nouveau bucket apparaît
tout seul dans Zabbix, sans rien reconfigurer.

---

## 2. Pourquoi WACM Connect et pas la « Stats API »

Wasabi a trois API, et elles ne s'adressent pas aux mêmes comptes :

| API | Pour qui | Authentification |
|---|---|---|
| Stats API | Comptes **standalone** uniquement | Access Key + Secret Key |
| **WACM Connect** | **Abonnés WACM** ← votre cas | **HTTP Basic** |
| S3 | Tout le monde | Access Key + Secret Key |

Votre compte est géré dans WACM : la Stats API répondra toujours `403`, quelle que
soit la clé générée. Inutile de chercher une « clé root ».

> Le dossier [`legacy/`](legacy/) contient une première version bâtie sur la Stats
> API. Elle n'a jamais été validée sur un compte réel et ne sert que pour un compte
> hors WACM.

---

## 3. La clé API

Elle se génère dans WACM, et il en existe deux types :

| Type | Où | Identifiant HTTP Basic |
|---|---|---|
| **Clé utilisateur** | Mon profil → WACM Connect | votre login WACM (`prenom.nom@societe.fr`) |
| **Clé de compte** | onglet Account (rôle Account Admin) | le nom du compte |

> ⚠️ **Le piège** : l'identifiant n'est **jamais** le nom que vous avez donné à la clé.
> Si vous avez appelé votre clé `ZABBIX`, `ZABBIX` ne sert à rien pour se connecter.

Une clé utilisateur ne voit que les comptes de votre périmètre. Si vos clients
n'apparaissent pas, c'est le signe qu'il faut une clé de compte.

> 🔒 La clé n'est affichée **qu'une seule fois**. Perdue, il faut la régénérer.

### Vérifier la clé

```powershell
.\tools\Test-WacmConnectApi.ps1 -Username votre.login@societe.fr -ApiKey VOTRE_CLE
```

Le script liste vos sous-comptes, leurs buckets, et enregistre les réponses brutes
dans `reponses-api\`. Si l'authentification passe, l'import peut suivre.

> ⚠️ Ces réponses contiennent des **données réelles** : identifiants de comptes,
> noms de clients, adresses e-mail, noms de buckets. Le `.gitignore` du dépôt exclut
> ce dossier. Ne les publie jamais — [`docs/api-samples/`](docs/api-samples/) contient
> des exemples anonymisés pour cela.

---

## 4. Importer le template

1. Zabbix : **Data collection → Templates**
2. **Import** (en haut à droite)
3. Fichier `template/wasabi_wacm_connect_by_http.yaml`
4. Cocher **Create new** partout → **Import**

Le template s'appelle **Wasabi WACM Connect by HTTP**, dans le groupe `Templates/Cloud`.
Zabbix 7.0 minimum (le tableau de bord utilise la grille à 72 colonnes).

### Mettre à jour un template déjà importé

Même chemin, mais cocher **Update existing** en plus de *Create new*.

Zabbix identifie les objets par leur **UUID**, pas par leur nom : les items
existants sont mis à jour et **conservent leur historique**, seuls les nouveaux
sont créés. C'est à cette condition que la mise à jour n'est pas destructive.

C'est aussi pourquoi le dépôt contient `src/build.py` : le template s'écrit dans
`src/template.src.yaml` avec des identifiants symboliques, le collecteur JavaScript
vit dans `src/collect.js`, et le script va chercher les UUID du template déjà publié
avant de produire la version finale. Pour modifier le template, modifie les sources
puis relance `python src/build.py` — jamais le YAML généré directement.

Après la mise à jour, pense au **Execute now** sur l'item maître : les nouveaux
items découverts restent vides jusqu'à la collecte suivante (§ 6).

---

## 5. Créer l'hôte

1. **Data collection → Hosts → Create host**
2. **Host name** : par exemple `Wasabi WACM`
3. **Templates** : `Wasabi WACM Connect by HTTP`
4. Onglet **Macros** → **Inherited and host macros** :

| Macro | Valeur |
|---|---|
| `{$WASABI.WACM.USER}` | votre login WACM |
| `{$WASABI.WACM.KEY}` | votre clé API |

Pas d'adresse IP ni d'agent : c'est le serveur Zabbix qui appelle
`https://api.wacm.wasabisys.com` en HTTPS sortant.

> La macro `{$WASABI.WACM.KEY}` est de type **Secret text** : une fois enregistrée,
> sa valeur n'est plus lisible dans l'interface.

---

## 6. Vérifier que ça remonte

**Monitoring → Latest data**, filtré sur votre hôte.

Pour ne pas attendre l'heure : ouvrez l'item **« Wasabi: Get WACM data »** et
cliquez sur **Execute now**.

Si l'item passe en rouge, survolez-le : le message d'erreur exact de l'API s'affiche.

Sous-comptes et buckets apparaissent quelques minutes après la première collecte
réussie.

---

## 7. Ce qui est surveillé

### Vue d'ensemble du parc

Un **tableau de bord** est livré avec le template (onglet *Dashboards* de l'hôte) :
stockage total, stockage supprimé facturé, occupation du quota vendu, nombre de
comptes et de buckets, egress 30 jours, durée de collecte, et les problèmes en cours.

Les agrégats existent aussi comme items, utilisables dans tes propres écrans :
stockage actif total, stockage supprimé total, quota total vendu, taux d'occupation
global, part de données supprimées, egress 30 jours du parc.

### Par sous-compte

- Stockage actif, stockage supprimé encore facturé, quota souscrit
- **Quota effectif** et sa **source** (`purchased`, `trial` ou `none`)
- **Taux d'occupation du quota** (%), calculé sur le quota effectif
- **Jours restants avant expiration de l'essai**
- Statut du compte (`PAID_ACCOUNT`, `SUSPENDED`, `PENDING_DELETION`…)
- Type de quota (*soft* = dépassement toléré, *hard* = écritures bloquées)
- MFA, SSO et FTP activés ou non
- Egress et ingress du jour, **egress cumulé sur 30 jours**
- Nombre de buckets
- Graphe stockage vs quota

> **Comptes en essai** : `purchasedStorageTB` est vide pour eux, c'est `trialQuotaTB`
> qui fait foi. Le template bascule automatiquement — sans quoi un client en essai
> n'aurait aucune surveillance de quota.

### Par bucket

- Stockage actif et stockage supprimé
- Volume écrit et volume lu
- Objets actifs et objets supprimés
- Egress et ingress du jour
- Appels API du jour
- Région
- **Bucket supprimé ou non**, et date de suppression
- Fraîcheur du relevé

---

## 8. Les alertes

| Alerte | Ce que ça veut dire |
|---|---|
| **Quota ≥ 75 / 90 / 100 %** | Trois niveaux, alignés sur les notifications que vous avez déjà réglées dans WACM. Les alertes sont chaînées : à 100 % vous ne recevez que la critique, pas les trois |
| **Compte en suppression** | Le sous-compte et toutes ses données vont disparaître. En `HIGH` volontairement |
| **Compte suspendu** | Accès aux données interrompu |
| **Bucket supprimé mais toujours facturé** | Wasabi facture 90 jours minimum. Le bucket n'existe plus, la facture continue. L'alerte s'éteint seule à la fin de la rétention |
| **Chute de volume > 20 %** | Suppression massive, lifecycle mal réglé, ou compromission |
| **MFA désactivé** | Contrôle de sécurité. Mettre `{$WASABI.MFA.ALERT}` à `0` pour le couper |
| **Relevé périmé > 48 h** | L'API ne produit plus de données |
| **Aucun sous-compte visible** | L'API répond mais ne renvoie rien : périmètre de clé trop étroit |
| **Essai expire dans moins de 7 jours** | Sans conversion en compte payant, le service s'arrête |
| **Essai expiré** | La période d'essai est dépassée |
| **Aucun quota défini** | Ni quota souscrit ni quota d'essai : pas de surveillance de capacité possible |
| **Egress 30 j > volume stocké** | Dépassement de la politique d'usage raisonnable Wasabi |
| **Liste des sous-comptes tronquée** | Le plafond est atteint : des clients ne sont plus supervisés |
| **Collecte proche du timeout** | Au-delà de 60 s toute la supervision Wasabi s'arrête |
| **Sous-compte ajouté** | Un client a été provisionné dans WACM |
| **Sous-compte disparu** | Suppression effective, ou perte de visibilité de la clé |

### Régler les seuils

| Macro | Défaut | Rôle |
|---|---|---|
| `{$WASABI.QUOTA.WARN}` | `75` | Premier seuil de quota (%) |
| `{$WASABI.QUOTA.HIGH}` | `90` | Deuxième seuil |
| `{$WASABI.QUOTA.CRIT}` | `100` | Quota dépassé |
| `{$WASABI.TRIAL.DAYS.WARN}` | `7` | Alerter quand un essai expire dans moins de N jours |
| `{$WASABI.DURATION.MAX}` | `45` | Durée de collecte (s) au-delà de laquelle on alerte |
| `{$WASABI.BUCKET.STORAGE.MAX}` | `10T` | Taille max d'un bucket |
| `{$WASABI.BUCKET.DROP.PCT}` | `20` | % de chute déclenchant l'alerte |
| `{$WASABI.DELETED.BILLED.MIN}` | `1G` | Seuil au-delà duquel on signale un bucket supprimé encore facturé |
| `{$WASABI.DATA.MAX_AGE}` | `48h` | Fraîcheur maximale d'un relevé |
| `{$WASABI.MFA.ALERT}` | `1` | `0` pour désactiver le contrôle MFA |

**Seuil différent pour un bucket précis** — utilisez un contexte de macro :

```
{$WASABI.BUCKET.STORAGE.MAX:"sauvegardes-veeam"} = 50T
```

### Limiter le périmètre

| Macro | Effet |
|---|---|
| `{$WASABI.SUBACCOUNT.STATUS}` | Ne traiter que certains statuts, ex. `PAID_ACCOUNT,ON_TRIAL`. **Économise des appels API** : le filtre s'applique avant d'aller chercher les buckets |
| `{$WASABI.SUBACCOUNT.MATCHES}` / `.NOT_MATCHES` | Filtrer les sous-comptes par nom (regex) |
| `{$WASABI.BUCKET.MATCHES}` / `.NOT_MATCHES` | Filtrer les buckets par nom (regex) |
| `{$WASABI.SUBACCOUNT.MAX}` | Nombre max de sous-comptes par collecte (défaut 50) |

---

## 9. Trois choses à savoir

**Les données datent d'hier.** Un relevé par jour. Ce template donne une vision de
la **capacité et des coûts**, pas du temps réel. Un bucket rempli il y a dix minutes
n'apparaîtra que demain. Pour du temps réel (le bucket répond-il ? en combien de
temps ?), il faut un contrôle S3 complémentaire — ce n'est pas l'objet ici.

**Les compteurs sont des totaux journaliers.** Egress, ingress et appels API
contiennent le total du jour, pas un compteur qui monte. Si vous ajoutez vos propres
items, ne leur appliquez **jamais** *Change per second*.

**Un appel API par sous-compte.** Avec beaucoup de clients, la collecte peut
approcher le timeout de 60 s. Utilisez `{$WASABI.SUBACCOUNT.STATUS}` pour écarter
les comptes inactifs.

### Sur les unités

L'API renvoie le stockage en **To** et le trafic en **Go**. Le template convertit en
octets avec **1 To = 10¹² octets** (To décimal, comme la facturation Wasabi).

Ces unités ne sont pas documentées côté Wasabi : elles ont été déduites par
recoupement sur vos propres données — la somme du `deletedStorage` des deux buckets
(`0,05800772577` + `0,000001017`) tombe exactement sur celui du sous-compte
(`0,05800874277`).

Si la console WACM affiche des valeurs différentes des graphes Zabbix, c'est le
multiplicateur qu'il faut ajuster : items concernés → *Preprocessing* → *Custom
multiplier*.

---

## 10. Si ça ne marche pas

| Symptôme | Cause probable |
|---|---|
| `401` | `{$WASABI.WACM.USER}` : c'est le **login WACM**, pas le nom de la clé |
| `403` | Clé valide mais droits insuffisants sur la ressource |
| Timeout | Zabbix n'atteint pas `api.wacm.wasabisys.com`. Renseignez `{$WASABI.HTTP.PROXY}` si vous passez par un proxy |
| « No sub-account visible » | Périmètre de la clé trop étroit → passer sur une clé de compte. Ou `{$WASABI.SUBACCOUNT.STATUS}` trop restrictif |
| Collecte trop longue | Trop de sous-comptes → filtrer par statut, ou baisser `{$WASABI.SUBACCOUNT.MAX}` |
| Aucun bucket découvert | Vérifier `{$WASABI.BUCKET.MATCHES}` et `{$WASABI.BUCKET.NOT_MATCHES}` |

Le message d'erreur complet est toujours visible en survolant l'item
**« Wasabi: Get WACM data »** dans *Latest data*.

---

## Documentation Wasabi

- [Quelle API Wasabi choisir](https://docs.wasabi.com/docs/which-wasabi-api-should-i-consider-using)
- [Authentification WACM Connect](https://docs.wasabi.com/apidocs/wacm-connect-api-authentication)
- [Générer une clé WACM Connect](https://docs.wasabi.com/apidocs/generating-a-wacm-connect-api-key)
- [Get Sub-Accounts](https://docs.wasabi.com/apidocs/get-sub-accounts)
- [Get Sub-Account Bucket Utilization](https://docs.wasabi.com/apidocs/get-sub-account-bucket-utilization)
