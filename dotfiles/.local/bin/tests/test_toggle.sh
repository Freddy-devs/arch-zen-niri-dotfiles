#!/bin/sh
# test_toggle.sh — prueba es_panel de zen-toggle y zen-close con procesos señuelo.
# Solo extrae la función (no ejecuta los scripts: zen-close cerraría la ventana enfocada) y mata
# cada señuelo por su pid.
bin=$(dirname "$(dirname "$(realpath "$0")")")
tmp=$(mktemp -d)
pids=
trap 'for p in $pids; do kill "$p" 2>/dev/null; done; rm -rf "$tmp"' EXIT
fallos=0

# scripts de python que solo duermen, con el nombre de un panel o de otra cosa
for n in zen-audio zen-ramx; do printf 'import time\ntime.sleep(30)\n' > "$tmp/$n"; done

# señuelo CMD…: lo lanza y espera a que haga exec (si no, /proc aún muestra la shell)
senuelo() {
    "$@" &
    pid=$!
    pids="$pids $pid"
    i=0
    while [ "$i" -lt 100 ] && [ "$(readlink "/proc/$pid/exe")" = "$(readlink /proc/$$/exe)" ]; do
        sleep 0.02; i=$((i + 1))
    done
}

for script in zen-toggle zen-close; do
    eval "$(sed -n '/^es_panel()/,/^}/p' "$bin/$script")"
    espera() {  # espera SI|NO NOMBRE PID DESCRIPCIÓN
        if es_panel "$2" "$3"; then r=SI; else r=NO; fi
        if [ "$r" = "$1" ]; then echo "ok   $script: $4"
        else echo "FALLA $script: $4 (esperaba $1)"; fallos=$((fallos + 1)); fi
    }
    senuelo python3 "$tmp/zen-audio";            espera SI zen-audio "$pid" "python3 …/zen-audio es el panel"
    senuelo python3 "$tmp/zen-audio" --waybar;   espera NO zen-audio "$pid" "python3 …/zen-audio --waybar no"
    senuelo python3 "$tmp/zen-ramx";             espera NO zen-ram "$pid" "zen-ramx no es zen-ram"
    senuelo sh -c 'exec -a "$0" sleep 30' zen-audio;   espera SI zen-audio "$pid" "argv[0] zen-audio (sin python)"
    senuelo sh -c 'exec -a "$0" sleep 30' nvim;        espera NO zen-audio "$pid" "nvim (pid reusado) no"
    senuelo sh -c 'exec -a "$0" sleep 30' /usr/bin/python3.14; espera NO zen-audio "$pid" "python sin script no"
    espera NO zen-audio "" "pid vacío no"
    espera NO zen-audio 999999999 "pid inexistente no"
done

[ "$fallos" = 0 ] && echo "todo bien" || { echo "$fallos fallos"; exit 1; }
