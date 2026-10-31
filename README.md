# Wild West Party Online

Tên hiển thị trong game: **Miền Tây Đại Chiến**.

Giao diện đã được Việt hóa: menu, tạo/tham gia phòng, phòng chờ, vai trò, lá bài, giai đoạn, trang bị, nhật ký, phản ứng, kết quả, thông báo lỗi và công cụ kiểm thử. Bản dịch tập trung trong localization/vi.gd (TextCatalog). Tên class, method, enum, ID lá bài, RPC và lệnh debug vẫn giữ tiếng Anh. Lỗi kết nối trên giao thức được dịch tại giao diện; tên người chơi do người dùng nhập được giữ nguyên.

Font ưu tiên Segoe UI, Arial, rồi DejaVu Sans cùng cơ chế font dự phòng của Godot. Bộ kiểm thử xác nhận các ký tự tiếng Việt có dấu. Khung bài, xuống dòng và cửa sổ phản ứng đã được điều chỉnh cho tiếng Việt ở 1440×900.

Kiểm tra bản dịch, font và bố cục:

    godot --headless --path . tests/LocalizationTest.tscn

Để kiểm tra bằng trình dựng đồ họa và lưu ảnh các màn hình vào tests/artifacts/vietnamese (không đưa vào Git):

    godot --path . tests/LocalizationTest.tscn -- --capture

A playable host-authoritative Godot 4.7.2 desktop prototype for a private group of friends. All graphics are generated from primitive meshes and materials. No external art or dependencies.

## Run and connect

Open project.godot in Godot 4.7.2 and press F6 on scenes/menu/MainMenu.tscn, or F5 to run the main scene.

1. Instance 1: choose HOST GAME, enter your name, keep port 7000, and press HOST.
2. Instances 2–4: choose JOIN GAME, enter a name, use 127.0.0.1 and port 7000, and press JOIN.
3. Everyone presses READY / NOT READY once. The host presses START GAME.
4. Read your private role and press CONTINUE.

For local testing, use the Godot editor's Debug > Customize Run Instances option, enable multiple instances and set the count to 4. Run the project and select Host in one window and Join in the other three. Alternatively, open four terminal windows and run:

    godot --path .

Debug/editor builds accept 2–4 ready players. The two-player test uses Sheriff versus Outlaw; three-player testing uses Sheriff, Outlaw and Renegade. Release builds require four players. Four-player roles are exactly one Sheriff, two Outlaws and one Renegade.

On a LAN, clients enter the host's LAN IP. Allow Godot through Windows Firewall on the appropriate private network. Internet hosting requires the host's UDP port (default 7000) forwarded to their computer, or an existing private VPN connection. There is no matchmaking or relay.

## Controls and rules

- Click a hand card to play it. Targeted cards highlight valid player panels and seat rings; click a highlighted panel to submit. Escape or CANCEL TARGET cancels.
- END TURN enters the discard phase when your hand exceeds your current HP. Click excess cards to discard; the turn advances automatically when the limit is met.
- During a reaction, use the offered Dodge, Drink or Shoot, or take the hit. The server expires the prompt after eight seconds.
- Your role and hand are private. The Sheriff is public; death reveals the fallen player's role. All roles are revealed at game over.
- Only the host can PLAY AGAIN or RETURN TO LOBBY. Any player can leave.

Everyone starts with four cards and 4 HP; the Sheriff has 5 HP. Each turn draws two. The 32-card deck includes Shoot, Dodge, Drink, Rifle, Horse, Spyglass, Lucky Barrel, Supply and Showdown. Shoot is limited to once per turn. Rifle grants range 2; Horse and Spyglass modify circular distance, skipping dead seats. A Barrel publicly reveals and discards the checked card. Equipment cannot be duplicated. Showdown alternates Shoot responses and ignores distance.

Emergency Drink restores a fatally wounded player to 1 HP. Death discards all possessions. Killing an Outlaw draws three cards. The future Deputy penalty is implemented. Sheriff death gives the Outlaws victory unless the Renegade is the sole survivor; eliminating all enemies gives the Sheriff team victory.

Disconnected players forfeit, reveal their role and discard their cards. No kill reward is granted for a disconnect. Turns and pending reactions resolve safely. Host departure ends the session.

## Architecture

- autoload/NetworkManager.gd: ENet setup, admission, connection errors and RPC transport. Remote actions derive the actor from the RPC sender ID.
- autoload/GameManager.gd: server-only player registry, lifecycle, validated intentions, death, victory and sanitized snapshots.
- scripts/game/: separate deck, distance, turns, reaction deadlines, effect dispatch and procedural table presentation.
- scripts/cards/: card definitions, effect/target/type enums and unique card instances.
- scripts/player/: gameplay-only PlayerState and visual-only PlayerAvatar.
- scripts/ui/App.gd: signal-driven menus, lobby, cards, player panels and overlays. The UI submits intentions and uses server-provided valid targets.
- scenes/menu/Lobby.tscn and scripts/ui/Lobby.gd: dedicated lobby screen with synchronized names, HOST badge, explicit ready status and host-only Start. Start requires enough players and every player ready. Hosting always opens this screen before gameplay. The selected server port appears in the lobby.
- resources/characters/characters.json: character definitions ready for future ability identifiers.

The host sends one sanitized public snapshot and separate rpc_id private snapshots. No opponent hands, hidden roles, draw order or server reaction context are broadcast. Valid target lists are sent only to the owner. RPC receive methods accept only the host authority. Requests are validated for ownership, phase, target, range, card existence and reaction ID, with a short per-peer action rate limit. Debug actions additionally require host identity and OS.is_debug_build(). Reveal Roles is a host-local notice.

The host is trusted and necessarily knows the entire match. Clients have no server player registry. This prototype does not provide encryption, anti-cheat against a modified host, account identity or reconnect tokens.

## Validation

With the Godot executable on PATH:

    godot --headless --path . --editor --quit
    godot --headless --path . --quit-after 5
    godot --headless --path . tests/RulesTest.tscn
    godot --headless --path . tests/PresentationTest.tscn

RulesTest performs 96 checks covering deck composition and reshuffling, role distribution, distance and equipment, turns, Shoot/Dodge/Drink, emergency survival, death rewards, Showdown, Barrel, privacy, all victories, restart, disconnects, malformed requests and reaction timeouts. PresentationTest constructs every screen and checks that the game layout fits the default viewport.

The four-process Windows integration test uses localhost UDP port 17070 and instantiates the actual application UI in every peer:

    powershell -NoProfile -ExecutionPolicy Bypass -File tests/RunNetworkTest.ps1 -Godot "C:/path/to/Godot_v4.7.2-stable_win64_console.exe"

It checks admission, names/ready state, four-player start, owner-only snapshots, automated legal gameplay, game-over delivery, match restart and return to lobby. Logs are written to tests/network-*.log and *.err. Its final victories are triggered deterministically on the host; combat itself is covered by RulesTest.

For the focused two-instance lobby test on 127.0.0.1:7000:

    powershell -NoProfile -ExecutionPolicy Bypass -File tests/RunNetworkTest.ps1 -Godot "C:/path/to/Godot_v4.7.2-stable_win64_console.exe" -TestScene tests/LobbyTest.tscn -ProcessCount 2

This presses the real UI controls and verifies Host → Lobby, Join → the same Lobby, synchronized names/ready/unready, host badge, host-only Start, minimum-player enforcement, disconnect/rejoin, synchronized GameTable loading and host-disconnect cleanup. Port 7000 must be available.

Use -ProcessCount 5 with the default NetworkTest scene to additionally check Server full rejection. Run godot --headless --path . tests/ConnectionFailureTest.tscn to check invalid IP/port and real ENet failure/timeout against unhosted localhost port 17071.

## Debug tools

Visible only to the host in debug builds: lobby Force Start (still requires at least two players), Reveal Roles, Give Shoot, Draw Card, Damage Player, Heal Player, Next Turn and Force Win Check. Select the target using the dropdown. Give Shoot creates a unique extra test card; restarting restores the normal deck.

## Known limitations and TODO

- Current lobby caps at four. Role tables support five to seven, while deck balance, lobby UI and admission must be expanded together.
- The lobby has a dedicated scene. Other UI screens and overlays are built in GDScript rather than separate editable scenes for each widget.
- Target selection uses player panels; 3D rings indicate targets but do not accept clicks.
- Avatars and animations remain stylized procedural placeholders; no character abilities, ragdolls or walking.
- No reconnect, host migration, spectator joining, save games, accounts, matchmaking or turn timer. Reaction timers continue while the role overlay is open.
- Desktop layout targets 1440×900. Very small windows and accessibility need a dedicated pass.
- Headless tests exercise UI construction and networking but do not replace a visual playtest or testing between separate computers.
- Future work: character ability registry, more card definitions, reusable UI scene assets, visual polish and release export presets.

## Nâng cấp hình ảnh saloon

- Menu dùng nền saloon vẽ bằng code, tông xanh đêm/nâu ấm, cửa sổ phát sáng, bụi bay nhẹ, tiêu đề nhấp sáng và nút có trạng thái rê chuột/nhấn.
- Phòng chờ có khung từng người theo màu ghế, trạng thái sẵn sàng màu xanh, số người hiện tại và bảng điều khiển tập trung.
- Bàn chơi có sàn ván gỗ, tường, xà gỗ, biển quán, đèn lồng, kệ chai, thùng rượu, bàn viền đồng và mặt nỉ xanh. Dùng một đèn hướng có bóng, một đèn lấp đầy không bóng, vật liệu dùng lại và mesh ít đa giác. Không dùng texture hoặc tài nguyên bên ngoài.
- Cao bồi có mắt, ria mép, khăn cổ, đai lưng, ủng và mũ quá khổ; màu áo, dải mũ và bệ ghế đồng bộ theo người chơi.
- Lá bài có khung giấy, dải tên theo loại, biểu tượng vẽ bằng code, chất/số, mô tả tiếng Việt, rê chuột nhấc nhẹ và viền vàng khi chọn mục tiêu.
- Camera giữ góc theo ghế, chuyển vị trí mượt và rung nhẹ khi trúng đòn. Mục tiêu hợp lệ có vòng vàng và bảng người chơi được đánh dấu.
- Hoạt ảnh gồm thở/lắc nhẹ, giật súng, né nghiêng người, trúng đòn lắc mũ, uống rượu nảy vui và ngã nghiêng. VFX gồm chớp súng, bụi/tia nhỏ, chữ −1/+1 và chữ NÉ.
- Cửa sổ vai trò/phản ứng có bảng riêng và hiệu ứng hiện nhẹ; màn hình kết quả có điểm nhấn vàng và câu đùa miền Tây.

Các file chính mới:

- scripts/ui/SaloonTheme.gd và SaloonBackdrop.gd: giao diện và nền chung.
- scenes/ui/CardUI.tscn, scripts/ui/CardView.gd: lá bài tái sử dụng.
- scripts/game/SaloonRoom.gd: căn phòng và bàn chơi.
- scenes/props/SaloonLantern.tscn, scripts/game/SaloonLantern.gd: đèn lồng.
- scripts/vfx/TableEffects.gd và scenes/vfx/FloatingText.tscn: VFX tự hủy.
- tests/VisualEffectsTest.tscn: kiểm tra hoạt ảnh, vòng mục tiêu, camera, khởi động lại và hoàn tất lượt.

Chạy kiểm tra hiệu ứng:

    godot --headless --path . tests/VisualEffectsTest.tscn
    godot --path . tests/VisualEffectsTest.tscn -- --capture

Ảnh kiểm tra lưu tại tests/artifacts/polish; ảnh các màn hình lưu bằng LocalizationTest --capture. Đây là file kiểm tra cục bộ, không đưa vào Git.

Giới hạn: chưa thêm âm thanh. App có signal presentation_feedback để gắn âm thanh nút sau này; sự kiện hình ảnh mạng hiện có dùng cho âm thanh hành động trong tương lai. Chưa dùng sương mù, bloom hoặc shader nặng; ánh sáng đèn lồng là vật liệu phát sáng, không tạo riêng từng nguồn sáng. Bóng hiện còn sắc. Giao diện ưu tiên 1440×900 và có cuộn ngang cho nhiều lá bài; màn hình nhỏ và các cấu hình máy khác cần kiểm tra thêm. Cần thêm artwork lá bài gốc và âm thanh nếu muốn phát hành.

Nâng cấp này chỉ thay phần trình bày; giữ nguyên RPC, networking, vai trò và luật chơi phía máy chủ.
