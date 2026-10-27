# Samsung Galaxy A80 (SM-A805F, r1q): Debian через dmb

Порт Debian 13 (trixie) на Galaxy A80 с mainline-ядром Linux 7.1
(дерево [sm7150-mainline](https://github.com/sm7150-mainline/linux)) и
графикой freedreno (Mesa, Adreno 618).

**Статус: этап 1, на железе ещё не проверялся.**

## Что ожидается

| Часть | Этап 1 (сейчас) | Как |
|---|---|---|
| Загрузка ядра 7.1 | ожидается | boot.img через Odin |
| Экран | текстовая консоль | framebuffer, оставленный загрузчиком (simple-framebuffer, 1080×2400) |
| Кнопки громкости и питания | ожидается | PM6150L GPIO 2, PM6150 PON |
| Хранилище UFS | ожидается | Debian на разделе `userdata` |
| USB | ожидается | только режим устройства: сеть RNDIS + COM-порт; SSH на 172.16.42.1 |
| GPU Adreno 618 (freedreno, turnip) | ожидается после `dmb-get-firmware` | без вывода на экран, проверка через `eglinfo` / `vulkaninfo` |
| Дисплей через DSI (msm DPU), яркость | нет | этап 2: драйвер панели AMS628RF05 (S6E3FC2) |
| Сенсор (IST40xx) | нет | этап 2 |
| Wi-Fi/Bluetooth (WCN3990), звук, модем, камеры, выдвижная камера, зарядка, датчики | нет | этап 3+ |

## Риски — прочитайте до прошивки

- **Knox.** Разблокировка загрузчика и любой неофициальный образ навсегда переводят счётчик Knox (e-fuse) в 0x1. Обратно его не вернуть даже стоковой прошивкой. Перестанут работать Samsung Pay/Pass, Secure Folder, часть Samsung Health.
- **Гарантия.** Samsung может отказать в гарантийном ремонте.
- **Данные.** Разблокировка загрузчика стирает телефон. Этап 2 (установка Debian) стирает раздел `userdata`, то есть всё в Android: фото, приложения, аккаунты. Сделайте резервную копию.
- **Загрузочная петля.** Неудачный `boot.img` или `dtbo.img` — телефон не загрузит Android, пока вы не прошьёте назад резервную копию или стоковую прошивку. Это поправимо, если режим Download работает (он работает всегда, он в загрузчике).
- **KG STATE.** Если в режиме Download написано `KG STATE: Prenormal`, загрузчик пропускает только официальные образы. Ничего не прошивайте, пока там не `Checking` или `Completed` (телефон должен побыть онлайн).
- Агент, который написал этот порт, телефон сам не прошивает: все шаги делаете вы.

## Что нужно

- Odin 3.14 (у вас `Desktop\Odin3-v3.14.1-3B-PatcheD`) и драйвер Samsung USB.
- Стоковая прошивка вашего региона (`A805F…`, например через SamFw или Frija) — путь назад.
- Ваш OrangeFox для r1q в разделе recovery и `adb` (у вас `Desktop\platform-tools`).
- PuTTY (уже установлен).
- Файлы из `work/out/samsung-r1q/` после `./dmb build`:
  - `dmb-samsung-r1q-boot.tar.md5` — Odin AP: boot.img (шаг 1, данные не трогает)
  - `dtbo-empty.img` — пустой dtbo, пишется **из OrangeFox через adb** (шаг 1)
  - `dmb-samsung-r1q-full.tar.md5` — Odin AP: boot.img + Debian в `userdata` (шаг 2, **стирает Android**)
  - `rootfs.img` — тот же Debian для установки через `adb` вместо Odin
  - `dtbo-lineage.img` — dtbo от LineageOS, чтобы снова грузился Android (лучше — ваша копия из OrangeFox)

Download-режим Samsung даже на разблокированном загрузчике принимает неподписанный boot.img, но **не принимает неподписанный dtbo**: Odin пишет `FAIL! (Auth)`. Поэтому dtbo пишется только из recovery, как это делает LineageOS.

Из WSL файлы видны в Windows по пути `\\wsl.localhost\Ubuntu\home\maxim\dmb\work\out\samsung-r1q\`.

## Сочетания кнопок A80

- **Download (Odin):** выключить, зажать **Громкость+ и Громкость−**, подключить USB-кабель к ПК.
- **Recovery (OrangeFox):** выключить, зажать **Громкость+ и Питание** (с подключённым кабелем).
- **Принудительная перезагрузка:** **Громкость− и Питание** 7–10 секунд.

## Шаг 0. Проверить загрузчик и сделать копии

1. Войдите в режим Download и сфотографируйте экран. Нужны строки `OEM LOCK` (должно быть `OFF (U)`), `KG STATE`, `CURRENT BINARY`.
2. Если загрузчик ещё заблокирован:
   1. Android → Настройки → О телефоне → Сведения о ПО → 7 раз нажать «Номер сборки».
   2. Параметры разработчика → «Заводская разблокировка» (OEM unlocking) включить.
   3. Выключить, войти в Download, **долго нажать Громкость+**, подтвердить Громкость+. Телефон сотрётся.
   4. После загрузки подключиться к интернету и проверить, что «Заводская разблокировка» видна и включена.
3. Если ставили LineageOS/OrangeFox по прошлым шагам, отключённый `vbmeta` уже стоит. Если телефон на стоке — сначала нужен отключённый vbmeta (ваш `r1q-dl/lineage/vbmeta.img` с флагами 3), иначе загрузчик не примет чужой boot.img.
4. В OrangeFox: **Backup → boot, dtbo, EFS** (EFS — это IMEI, храните копию отдельно на ПК).

## Шаг 1. Тест загрузки ядра (данные Android не трогаются)

boot.img ищет Debian в `userdata`. Там пока Android, поэтому initramfs смотрит туда **только для чтения**, ничего не меняет и открывает отладочную консоль.

Загрузчик A80 при каждой загрузке накладывает оверлей из раздела `dtbo` на DTB ядра (в его логе: `Apply Overlay`, `dtbo_idx=8`). Стоковый оверлей рассчитан на downstream-ядро и на mainline-DTB не накладывается — телефон сразу уходит в Download. Поэтому нужен **пустой dtbo**. OrangeFox с ним работает как раньше (у recovery свой dtbo внутри образа). Android не загрузится, пока не вернёте dtbo и boot из копии.

1. Download-режим, Odin → **AP** = `dmb-samsung-r1q-boot.tar.md5`, Options: Auto Reboot **выключен**, Re-Partition выключен → **Start**.
2. После `PASS` сразу в recovery: Громкость− + Питание, как только экран погаснет — Громкость+ + Питание. В OrangeFox на ПК:
   ```bat
   adb push C:\Users\maxim\Desktop\GalaxyA80-dmb\dtbo-empty.img /dev/block/bootdevice/by-name/dtbo
   adb shell sync
   adb reboot
   ```
3. Телефон перезагрузится: логотип Samsung и предупреждение о разблокировке, затем на экране должны пойти строки ядра и сообщения `dmb: ...`, в конце `debug shell: ... holds no dmb rootfs`.
3. **Сфотографируйте экран** через 10 секунд и через минуту.
4. Не отключая кабель от ПК, откройте «Диспетчер устройств»:
   - «Порты (COM и LPT)» → новый «Устройство с последовательным интерфейсом USB (COMx)»;
   - «Сетевые адаптеры» → «Remote NDIS…».
5. PuTTY → Connection type **Serial**, Serial line `COMx`, Speed `115200`. В Session → Logging выберите **All session output** и файл, например `Desktop\a80-step1.log`. Нажмите Enter, должна появиться `#`.
6. Выполните и пришлите мне лог-файл:
   ```sh
   cat /run/dmb-initramfs.log
   uname -a
   cat /proc/cmdline
   dmesg
   ls -l /dev/dri /dev/sd* /sys/class/udc
   cat /sys/class/graphics/fb0/virtual_size
   ```
   Вместо COM-порта можно PuTTY → Telnet → `172.16.42.1`.
7. Вернуть Android: OrangeFox → Restore → boot и dtbo (из шага 0). Без копии dtbo: `adb push C:\Users\maxim\Desktop\GalaxyA80-dmb\dtbo-lineage.img /dev/block/bootdevice/by-name/dtbo`.

### Если что-то пошло не так

| Что видно | Что делать |
|---|---|
| Сразу снова Download, хотя записаны boot и пустой dtbo | Сфотографируйте экран Download. Затем прошейте `dmb-test-lineage-kernel.tar.md5` (ядро LineageOS + dmb initramfs): если и он уходит в Download, виновата упаковка boot.img, если нет — mainline-ядро или DTB. |
| Чёрный экран, телефон висит | Подождите минуту, принудительно перезагрузитесь **сразу в recovery**. В OrangeFox через ПК: `adb pull /sys/fs/pstore C:\Users\maxim\Desktop\a80-pstore` и пришлите папку: там лог ядра с прошлой загрузки. |
| Экран со строками, но COM-порта нет | Сфотографируйте экран: строки `dmb:` покажут, на каком шаге застряло. |

## Шаг 2. Установка Debian (стирает Android)

Только после удачного шага 1 (пустой dtbo уже стоит). Два способа, результат одинаковый.

**Через Odin (проще).** Download-режим, Odin → **AP** = `dmb-samsung-r1q-full.tar.md5` (≈500 МБ), Auto Reboot включён, Re-Partition выключен → **Start**. Внутри boot.img и `userdata.img.ext4.lz4`: Debian в формате Android sparse, как Samsung поставляет `userdata` в стоковых прошивках. Odin запишет его поверх раздела `userdata`, после перезагрузки сразу стартует Debian. Если Odin и на нём напишет `FAIL! (Auth)` — используйте второй способ.

**Через OrangeFox и adb.**

1. Recovery (OrangeFox). Если OrangeFox спросит пароль — нажмите «Отмена».
2. На ПК в `platform-tools`:
   ```bat
   adb shell umount /data
   adb push C:\Users\maxim\Desktop\GalaxyA80-dmb\rootfs.img /dev/block/bootdevice/by-name/userdata
   adb shell sync
   ```
   Образ 3 ГБ идёт по USB 2.0 несколько минут. **Не делайте после этого «Format Data» в OrangeFox** — это сотрёт Debian.
3. Перезагрузите в систему (boot.img из шага 1 должен стоять). При первом запуске файловая система растянется на весь раздел.
4. На ПК: `ssh user@172.16.42.1`, пароль `147147` (поменяйте: `passwd`). Или PuTTY на COM-порт — там будет обычный вход Debian.

## Шаг 3. freedreno

```sh
sudo dmb-get-firmware      # копирует a615_zap и DSP-прошивки с разделов vendor/apnhlos
sudo reboot
# после перезагрузки:
dmesg | grep -iE "msm|adreno|zap"
EGL_PLATFORM=surfaceless eglinfo -B | grep -iE "renderer|version"
vulkaninfo --summary
```

Ожидается `FD618` в OpenGL ES и `Turnip Adreno (TM) 618` в Vulkan. Пришлите вывод.

## Вернуться на Android

Odin → BL/AP/CP/CSC из стоковой прошивки (CSC, не HOME_CSC — с полной очисткой). Knox останется 0x1.

## Откуда данные для порта

- Карта памяти, регуляторы UFS/USB, GPIO кнопок: стоковый DTB (`qcom,msm-id <365 0>`) и оверлеи `dtbo.img` (board-id 0x22, ревизии до PV2), разобранные `tools/dtbo-dump.py`.
- Формат boot.img (header v1, база 0, board `SRPSA18B007`): загрузочный образ LineageOS для r1q.
- Схема питания та же, что у Pixel 4a (PM6150 + PM6150L), за основу DTS взят `sm7150-google-sunfish.dts`.
