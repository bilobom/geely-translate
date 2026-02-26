# Outil APK Interactif

Script principal: `apk_menu_fr.sh`  
Auteur: **[bilang](https://www.tiktok.com/@bilang042)**

Ce projet fournit un utilitaire Bash interactif (menu en francais) pour:

- Decompiler des APK
- Recompiler des dossiers decompiles
- Signer des APK compiles
- Installer les prerequis sur Debian/Ubuntu

## Fonctionnalites

- Interface terminal interactive en francais
- Selection par numero ou nom
- Selection multiple (espaces ou virgules) pour decompiler/compiler/signer
- Mot-cle `tout` pour selectionner tous les elements (dans les listes d'apps)
- Signature via `.pk8 + .pem` si disponibles
- Fallback automatique vers keystore JKS si besoin
- Gestion des conflits en decompilation: `Override`, `Rename` (suggestion `nom+numero`) et `Proteger res`

## Arborescence

```text
.
├── apk_menu_fr.sh
├── certificates/
│   ├── platform.pk8
│   └── platform.x509.pem
├── originalApk/   # APK source a decompiler
├── decompiled/    # dossiers decompiles
├── compiled/      # APK recompiles
└── signed/        # APK signes
```

## Prerequis

Le script peut installer les paquets requis via son menu.

Paquets attendus:

- `apktool`
- `apksigner`
- `zipalign`
- `default-jdk`
- `adb`

## Demarrage Rapide

1. Rendre le script executable:

```bash
chmod +x apk_menu_fr.sh
```

2. Lancer:

```bash
./apk_menu_fr.sh
```

3. Si necessaire, choisir `4) Installer les prerequis`.

## Menus

Menu principal:

1. `Decompiler` (`originalApk -> decompiled`)
2. `Compiler` (`decompiled -> compiled`)
3. `Signer` (`compiled -> signed`)
4. `Installer les prerequis` (Debian/Ubuntu)
5. `Quitter`

### 1) Decompiler

- Source: fichiers `.apk` dans `originalApk/`
- Destination: dossier dans `decompiled/`
- Selection: numero, nom, ou multiple

Si le dossier cible existe deja, sous-menu:

1. `Override`: ecrase le dossier existant
2. `Rename`: demande un nouveau nom (suggestion: `nom+numero`)
3. `Proteger res`: ecrase, mais restaure ensuite l'ancien `res/`

Mode `Proteger res`:

- Sauvegarde `decompiled/<app>/res`
- Lance la decompilation avec overwrite
- Remet l'ancien `res/` a la fin
- Meme en cas d'echec de decompilation, `res/` est restaure

### 2) Compiler

- Source: dossiers de `decompiled/`
- Sortie: `compiled/<nom>.apk`

### 3) Signer

- Source: APK de `compiled/`
- Sortie: `signed/<nom>-signed.apk`
- `zipalign` est tente avant la signature (si disponible)

Priorite de signature:

1. Paire `.pk8 + .pem` dans `certificates/` (si paire valide detectee)
2. Sinon keystore JKS `certificates/bilang-debug.jks`

### 4) Installer les prerequis

Le sous-menu affiche l'etat de chaque paquet (`installe` ou `manquant`) et propose:

- Installer tous les paquets manquants
- Installer un paquet precis (par numero ou nom)
- Retour au menu principal

## Regles de Selection

Exemples valides:

- `1`
- `GeelyAutoSettings`
- `1 3 5`
- `AppA,AppB`
- `tout` (pour les listes d'apps)

## Signature: variables utiles

Fallback JKS (par defaut):

- Keystore: `certificates/bilang-debug.jks`
- Alias: `bilang`
- Mot de passe store: `KEYSTORE_PASS` (defaut: `android`)
- Mot de passe cle: `KEY_PASS` (defaut: `android`)

Exemple:

```bash
KEYSTORE_PASS=monpass KEY_PASS=monpass ./apk_menu_fr.sh
```

## Workflow Type

1. Mettre les APK sources dans `originalApk/`
2. Lancer `./apk_menu_fr.sh`
3. Decompiler (option `1`)
4. Modifier `decompiled/<app>/`
5. Compiler (option `2`)
6. Signer (option `3`)
7. Recuperer l'APK final dans `signed/`

## Depannage

- Message `apktool introuvable` ou `apksigner introuvable`: utiliser l'option `4` pour installer les paquets manquants.
- Signature en fallback JKS alors que des certificats existent: verifier qu'une paire `.pk8/.pem` valide est bien detectable.
- Echec de decompilation/compilation: verifier que l'APK source n'est pas corrompu ou vide.

## Avertissement

Utilisez cet outil uniquement sur des APK que vous etes autorise a modifier et signer.
