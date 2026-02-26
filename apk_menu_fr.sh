#!/usr/bin/env bash

# Auteur: bilang
# Outil interactif APK pour Debian/Ubuntu

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_DIR="$BASE_DIR/originalApk"
DECOMPILED_DIR="$BASE_DIR/decompiled"
COMPILED_DIR="$BASE_DIR/compiled"
SIGNED_DIR="$BASE_DIR/signed"
CERT_DIR="$BASE_DIR/certificates"

KEYSTORE_PATH="$CERT_DIR/bilang-debug.jks"
KEY_ALIAS="bilang"
KEYSTORE_PASS="${KEYSTORE_PASS:-android}"
KEY_PASS="${KEY_PASS:-android}"
SIGN_KEY_PATH=""
SIGN_CERT_PATH=""

SELECTED_ITEMS=()

mkdir -p "$ORIGINAL_DIR" "$DECOMPILED_DIR" "$COMPILED_DIR" "$SIGNED_DIR" "$CERT_DIR"

pause() {
  read -rp "Appuyez sur Entree pour continuer..." _
}

cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

confirm() {
  local answer
  read -rp "$1 [o/N]: " answer
  answer="${answer,,}"
  [[ "$answer" == "o" || "$answer" == "oui" || "$answer" == "y" || "$answer" == "yes" ]]
}

show_items() {
  local -n list_ref="$1"
  local i=1
  for item in "${list_ref[@]}"; do
    printf "  %d) %s\n" "$i" "$item"
    ((i++))
  done
}

choose_items() {
  local title="$1"
  local -n source_items="$2"
  local allow_all="${3:-1}"

  SELECTED_ITEMS=()

  if ((${#source_items[@]} == 0)); then
    echo "Aucun element disponible pour: $title"
    return 1
  fi

  while true; do
    echo
    echo "$title"
    show_items source_items
    if [[ "$allow_all" -eq 1 ]]; then
      echo "Astuce: tapez 'tout' pour tout selectionner."
    fi
    read -rp "Choix (numero(s) ou nom(s), espaces/virgules): " raw
    raw="${raw//,/ }"

    read -r -a tokens <<< "$raw"
    if ((${#tokens[@]} == 0)); then
      echo "Selection vide, recommencez."
      continue
    fi

    local -a chosen=()
    local invalid=0
    declare -A seen=()

    for token in "${tokens[@]}"; do
      [[ -z "$token" ]] && continue

      local picked=""
      local token_lc="${token,,}"

      if [[ "$allow_all" -eq 1 && "$token_lc" == "tout" ]]; then
        chosen=("${source_items[@]}")
        invalid=0
        break
      fi

      if [[ "$token" =~ ^[0-9]+$ ]]; then
        local idx=$((token - 1))
        if ((idx < 0 || idx >= ${#source_items[@]})); then
          echo "Numero hors plage: $token"
          invalid=1
          break
        fi
        picked="${source_items[$idx]}"
      else
        for item in "${source_items[@]}"; do
          local item_lc="${item,,}"
          local base_lc="${item_lc%.apk}"
          if [[ "$token_lc" == "$item_lc" || "$token_lc" == "$base_lc" ]]; then
            picked="$item"
            break
          fi
        done
        if [[ -z "$picked" ]]; then
          echo "Nom non trouve: $token"
          invalid=1
          break
        fi
      fi

      if [[ -n "$picked" && -z "${seen[$picked]:-}" ]]; then
        chosen+=("$picked")
        seen["$picked"]=1
      fi
    done

    if ((invalid)); then
      continue
    fi
    if ((${#chosen[@]} == 0)); then
      echo "Aucun element valide."
      continue
    fi

    SELECTED_ITEMS=("${chosen[@]}")
    return 0
  done
}

ensure_keystore() {
  if [[ -f "$KEYSTORE_PATH" ]]; then
    return 0
  fi

  if ! cmd_exists keytool; then
    echo "Erreur: 'keytool' est requis pour creer le certificat."
    return 1
  fi

  echo "Creation du keystore: $KEYSTORE_PATH"
  keytool -genkeypair \
    -keystore "$KEYSTORE_PATH" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -storepass "$KEYSTORE_PASS" \
    -keypass "$KEY_PASS" \
    -dname "CN=bilang, OU=tools, O=bilang, L=Paris, ST=Ile-de-France, C=FR" >/dev/null 2>&1
}

resolve_pk8_pem_pair() {
  SIGN_KEY_PATH=""
  SIGN_CERT_PATH=""

  local -a pk8_files=()
  local -a pem_files=()
  local -a pair_keys=()
  local -a pair_certs=()

  mapfile -t pk8_files < <(find "$CERT_DIR" -maxdepth 1 -type f -name "*.pk8" | sort -f)
  mapfile -t pem_files < <(find "$CERT_DIR" -maxdepth 1 -type f -name "*.pem" | sort -f)

  if ((${#pk8_files[@]} == 0 || ${#pem_files[@]} == 0)); then
    return 1
  fi

  if ((${#pk8_files[@]} == 1 && ${#pem_files[@]} == 1)); then
    SIGN_KEY_PATH="${pk8_files[0]}"
    SIGN_CERT_PATH="${pem_files[0]}"
    return 0
  fi

  for pk8 in "${pk8_files[@]}"; do
    local pk8_name
    local pk8_base
    pk8_name="$(basename "$pk8")"
    pk8_base="${pk8_name%.pk8}"

    for pem in "${pem_files[@]}"; do
      local pem_name
      local pem_base
      pem_name="$(basename "$pem")"
      pem_base="${pem_name%.pem}"
      pem_base="${pem_base%.x509}"

      if [[ "$pk8_base" == "$pem_base" ]]; then
        pair_keys+=("$pk8")
        pair_certs+=("$pem")
      fi
    done
  done

  if ((${#pair_keys[@]} == 1)); then
    SIGN_KEY_PATH="${pair_keys[0]}"
    SIGN_CERT_PATH="${pair_certs[0]}"
    return 0
  fi

  return 2
}

suggest_numbered_name() {
  local base_name="$1"
  local num=1
  local candidate

  while true; do
    candidate="${base_name}${num}"
    if [[ ! -e "$DECOMPILED_DIR/$candidate" ]]; then
      printf "%s" "$candidate"
      return 0
    fi
    ((num++))
  done
}

action_decompile() {
  if ! cmd_exists apktool; then
    echo "Erreur: apktool introuvable. Utilisez d'abord le menu d'installation."
    pause
    return
  fi

  mapfile -t apk_files < <(find "$ORIGINAL_DIR" -maxdepth 1 -type f -iname "*.apk" -printf "%f\n" | sort -f)
  if ! choose_items "Selection des APK a decompiler (source: originalApk)" apk_files 1; then
    pause
    return
  fi

  local ok=0
  local ko=0
  for apk_file in "${SELECTED_ITEMS[@]}"; do
    local in_apk="$ORIGINAL_DIR/$apk_file"
    local app_name="${apk_file%.apk}"
    local target_name="$app_name"
    local out_dir="$DECOMPILED_DIR/$target_name"
    local decompile_mode="override"

    if [[ -d "$out_dir" ]]; then
      while true; do
        local suggested_name
        suggested_name="$(suggest_numbered_name "$app_name")"
        echo
        echo "Avertissement: '$target_name' existe deja dans decompiled."
        echo "1) Override (ecraser le dossier existant)"
        echo "2) Rename (nouveau nom, suggestion: $suggested_name)"
        echo "3) Proteger res (override + conserver le dossier res existant)"
        read -rp "Choisissez une option: " exists_choice

        case "${exists_choice,,}" in
          1|override|o|ecraser)
            decompile_mode="override"
            break
            ;;
          2|rename|r|renommer)
            read -rp "Nouveau nom [${suggested_name}]: " new_name
            new_name="${new_name:-$suggested_name}"
            if [[ "$new_name" == */* || "$new_name" == *$'\n'* ]]; then
              echo "Nom invalide: utilisez un nom simple sans '/'."
              continue
            fi
            if [[ -e "$DECOMPILED_DIR/$new_name" ]]; then
              echo "Le nom '$new_name' existe deja, choisissez un autre nom."
              continue
            fi
            target_name="$new_name"
            out_dir="$DECOMPILED_DIR/$target_name"
            decompile_mode="override"
            break
            ;;
          3|protect|proteger|p|res)
            decompile_mode="protect_res"
            break
            ;;
          *)
            echo "Option invalide."
            ;;
        esac
      done
    fi

    local backup_root=""
    local backup_res=""
    if [[ "$decompile_mode" == "protect_res" && -d "$out_dir/res" ]]; then
      backup_root="$(mktemp -d "/tmp/${target_name}.res_backup.XXXXXX")"
      if cp -a "$out_dir/res" "$backup_root/"; then
        backup_res="$backup_root/res"
        echo "Protection active: dossier res sauvegarde."
      else
        echo "Impossible de sauvegarder res, mode override normal applique."
        rm -rf "$backup_root"
        backup_root=""
        backup_res=""
        decompile_mode="override"
      fi
    fi

    echo "Decompilation: $apk_file -> decompiled/$target_name"
    if apktool d -f "$in_apk" -o "$out_dir"; then
      if [[ "$decompile_mode" == "protect_res" && -d "$backup_res" ]]; then
        rm -rf "$out_dir/res"
        mv "$backup_res" "$out_dir/res"
        echo "Dossier res restaure apres override."
      fi
      ((ok++))
    else
      if [[ "$decompile_mode" == "protect_res" && -d "$backup_res" ]]; then
        mkdir -p "$out_dir"
        rm -rf "$out_dir/res"
        mv "$backup_res" "$out_dir/res"
        echo "Echec decompilation: dossier res restaure."
      fi
      ((ko++))
    fi

    [[ -n "$backup_root" ]] && rm -rf "$backup_root"
  done

  echo "Resultat decompilation - Succes: $ok, Echecs: $ko"
  pause
}

action_compile() {
  if ! cmd_exists apktool; then
    echo "Erreur: apktool introuvable. Utilisez d'abord le menu d'installation."
    pause
    return
  fi

  mapfile -t app_dirs < <(find "$DECOMPILED_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort -f)
  if ! choose_items "Selection des apps a compiler (source: decompiled)" app_dirs 1; then
    pause
    return
  fi

  local ok=0
  local ko=0
  for app_name in "${SELECTED_ITEMS[@]}"; do
    local in_dir="$DECOMPILED_DIR/$app_name"
    local out_apk="$COMPILED_DIR/$app_name.apk"
    echo "Compilation: decompiled/$app_name -> compiled/$app_name.apk"
    if apktool b "$in_dir" -o "$out_apk"; then
      ((ok++))
    else
      ((ko++))
    fi
  done

  echo "Resultat compilation - Succes: $ok, Echecs: $ko"
  pause
}

action_sign() {
  if ! cmd_exists apksigner; then
    echo "Erreur: apksigner introuvable. Utilisez d'abord le menu d'installation."
    pause
    return
  fi

  mapfile -t compiled_apks < <(find "$COMPILED_DIR" -maxdepth 1 -type f -iname "*.apk" -printf "%f\n" | sort -f)
  if ! choose_items "Selection des APK a signer (source: compiled)" compiled_apks 1; then
    pause
    return
  fi

  local sign_mode="jks"
  if resolve_pk8_pem_pair; then
    sign_mode="pk8pem"
    echo "Paire de signature detectee:"
    echo "  Cle : $(basename "$SIGN_KEY_PATH")"
    echo "  Certificat : $(basename "$SIGN_CERT_PATH")"
  else
    local pair_status=$?
    if [[ "$pair_status" -eq 2 ]]; then
      echo "Plusieurs paires .pk8/.pem detectees. Utilisation du keystore JKS."
    else
      echo "Aucune paire .pk8/.pem detectee. Utilisation du keystore JKS."
    fi
    if ! ensure_keystore; then
      echo "Impossible de preparer le keystore."
      pause
      return
    fi
  fi

  local ok=0
  local ko=0

  for apk_file in "${SELECTED_ITEMS[@]}"; do
    local in_apk="$COMPILED_DIR/$apk_file"
    local app_name="${apk_file%.apk}"
    local out_apk="$SIGNED_DIR/$app_name-signed.apk"
    local sign_input="$in_apk"
    local tmp_aligned=""

    if cmd_exists zipalign; then
      tmp_aligned="$(mktemp "/tmp/${app_name}.aligned.XXXXXX.apk")"
      if zipalign -f 4 "$in_apk" "$tmp_aligned"; then
        sign_input="$tmp_aligned"
      else
        echo "zipalign a echoue pour $apk_file, signature sans alignement."
        rm -f "$tmp_aligned"
        tmp_aligned=""
      fi
    fi

    echo "Signature: compiled/$apk_file -> signed/$app_name-signed.apk"
    if [[ "$sign_mode" == "pk8pem" ]]; then
      if apksigner sign \
        --key "$SIGN_KEY_PATH" \
        --cert "$SIGN_CERT_PATH" \
        --out "$out_apk" \
        "$sign_input" &&
        apksigner verify "$out_apk" >/dev/null; then
        ((ok++))
      else
        ((ko++))
      fi
    else
      if apksigner sign \
        --ks "$KEYSTORE_PATH" \
        --ks-key-alias "$KEY_ALIAS" \
        --ks-pass "pass:$KEYSTORE_PASS" \
        --key-pass "pass:$KEY_PASS" \
        --out "$out_apk" \
        "$sign_input" &&
        apksigner verify "$out_apk" >/dev/null; then
        ((ok++))
      else
        ((ko++))
      fi
    fi

    [[ -n "$tmp_aligned" ]] && rm -f "$tmp_aligned"
  done

  echo "Resultat signature - Succes: $ok, Echecs: $ko"
  pause
}

action_install_requirements() {
  local -a required=(apktool apksigner zipalign default-jdk adb)

  while true; do
    local -a missing=()
    local -a status_lines=()
    local i=1

    for pkg in "${required[@]}"; do
      if dpkg -s "$pkg" >/dev/null 2>&1; then
        status_lines+=("  $i) $pkg [installe]")
      else
        status_lines+=("  $i) $pkg [manquant]")
        missing+=("$pkg")
      fi
      ((i++))
    done

    clear
    echo "========================================"
    echo " Installation des prerequis (Debian)"
    echo "========================================"
    printf "%s\n" "${status_lines[@]}"
    echo
    echo "Actions:"
    echo "  1) Installer tous les paquets manquants"
    local opt=2
    for pkg in "${required[@]}"; do
      if dpkg -s "$pkg" >/dev/null 2>&1; then
        echo "  $opt) Installer $pkg [installe]"
      else
        echo "  $opt) Installer $pkg [manquant]"
      fi
      ((opt++))
    done
    local return_opt="$opt"
    echo "  $return_opt) Retour"

    read -rp "Choisissez une option (numero ou nom du paquet): " sub_choice
    local sub_choice_lc="${sub_choice,,}"

    if [[ "$sub_choice_lc" == "1" || "$sub_choice_lc" == "tout" || "$sub_choice_lc" == "all" || "$sub_choice_lc" == "a" ]]; then
      if ((${#missing[@]} == 0)); then
        echo "Tous les prerequis sont deja installes."
        pause
        continue
      fi

      echo "Paquets manquants: ${missing[*]}"
      if ! confirm "Lancer l'installation de tous les paquets manquants ?"; then
        echo "Installation annulee."
        pause
        continue
      fi

      if ! cmd_exists sudo; then
        echo "Erreur: sudo introuvable."
        pause
        continue
      fi

      if sudo apt-get update && sudo apt-get install -y "${missing[@]}"; then
        echo "Installation terminee."
      else
        echo "Installation incomplte. Verifiez les messages d'erreur apt."
      fi
      pause
      continue
    fi

    if [[ "$sub_choice_lc" == "$return_opt" || "$sub_choice_lc" == "retour" || "$sub_choice_lc" == "r" || "$sub_choice_lc" == "q" || "$sub_choice_lc" == "quit" || "$sub_choice_lc" == "quitter" || "$sub_choice_lc" == "exit" ]]; then
      return
    fi

    local selected_pkg=""
    if [[ "$sub_choice" =~ ^[0-9]+$ ]]; then
      local idx=$((sub_choice - 2))
      if ((idx >= 0 && idx < ${#required[@]})); then
        selected_pkg="${required[$idx]}"
      fi
    else
      for pkg in "${required[@]}"; do
        if [[ "${pkg,,}" == "$sub_choice_lc" ]]; then
          selected_pkg="$pkg"
          break
        fi
      done
    fi

    if [[ -z "$selected_pkg" ]]; then
      echo "Option invalide."
      pause
      continue
    fi

    if dpkg -s "$selected_pkg" >/dev/null 2>&1; then
      echo "$selected_pkg est deja installe."
      pause
      continue
    fi

    if ! confirm "Installer le paquet '$selected_pkg' ?"; then
      echo "Installation annulee."
      pause
      continue
    fi

    if ! cmd_exists sudo; then
      echo "Erreur: sudo introuvable."
      pause
      continue
    fi

    if sudo apt-get update && sudo apt-get install -y "$selected_pkg"; then
      echo "Installation de '$selected_pkg' terminee."
    else
      echo "Echec d'installation pour '$selected_pkg'."
    fi
    pause
  done
}

show_menu() {
  clear
  cat <<'EOF'
========================================
  Outil APK Interactif (Auteur: bilang)
========================================
1) Decompiler (source: originalApk -> decompiled)
2) Compiler   (source: decompiled  -> compiled)
3) Signer     (source: compiled    -> signed)
4) Installer les prerequis (Debian/Ubuntu)
5) Quitter
EOF
}

main() {
  while true; do
    show_menu
    read -rp "Choisissez une option: " choice
    case "${choice,,}" in
      1|decompiler|decompile|d)
        action_decompile
        ;;
      2|compiler|compile|c)
        action_compile
        ;;
      3|signer|sign|s)
        action_sign
        ;;
      4|installer|install|prerequis|requirements|r)
        action_install_requirements
        ;;
      5|q|quit|quitter|exit)
        echo "Au revoir."
        exit 0
        ;;
      *)
        echo "Option invalide."
        pause
        ;;
    esac
  done
}

main "$@"
