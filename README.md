# Miền Tây Đại Chiến

Project Godot 4.7.2, client Web + server Godot headless có thẩm quyền, giao diện tiếng Việt và saloon 3D tạo bằng primitive. Không dùng artwork bên ngoài. ENet được giữ cho kiểm thử desktop; giao diện người chơi mặc định dùng WebSocket và mã phòng.

## Web multiplayer cục bộ

Đã chuẩn bị build tại build/web. Khi server và web server đang chạy, mở:

    http://127.0.0.1:8080

Nhập tên → TẠO PHÒNG → sao chép mã 6 ký tự. Người khác mở cùng URL, nhập tên + mã → THAM GIA. Ready và Start diễn ra trong phòng chung. Không nhập IP hoặc cổng trong giao diện.

Tái tạo build (Godot 4.7.2 và Node 22+):

    node tools/fetch-web-templates.cjs
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/Export-Web.ps1 -Godot "C:/path/to/Godot_v4.7.2-stable_win64_console.exe"

Script tải chỉ lấy hai template Web không luồng từ bản phát hành chính thức, kiểm tra CRC của entry ZIP và lưu vào build/templates. Không cần cài template toàn nền tảng vào hồ sơ người dùng.

Chạy hai terminal tại thư mục project:

    godot --headless --path . server/DedicatedServer.tscn -- --development

    node tools/serve-web.cjs

Hoặc chạy tools/Run-Local-Web.ps1 -Godot "C:/path/to/Godot.exe" để khởi động hai tiến trình ẩn và in PID. Dừng đúng hai PID được in khi không cần nữa. Server mặc định chỉ lắng nghe 127.0.0.1:7000; HTTP chỉ lắng nghe 127.0.0.1:8080.

Mặc định 4–7 người; chỉ server có --development trong debug build mới cho phép đúng 2 người. Host là chủ phòng và có thể chuyển sang người đang kết nối khác; vai trò trong game được xáo riêng, không đổi khi chuyển chủ phòng.

Endpoint tập trung trong config/network.cfg (desktop client), web/network-config.js (Web), hoặc WWPO_SERVER_URL (desktop). HTTPS dùng WSS; cấu hình mẫu trỏ WSS cùng origin /ws để dùng với TLS reverse proxy sau này. Mốc hiện tại chỉ chạy local, chưa có triển khai cloud hay public.

Refresh tab khôi phục bằng sessionStorage của tab. Mất socket được giữ chỗ 45 giây; reconnect khôi phục đúng ID, tay bài, vai trò và nhân vật. Menu/đồng hồ server vẫn chạy. Sau thời gian chờ, áp dụng đường xử lý bỏ cuộc hiện có. Phiên và phòng lưu trong RAM, không phục hồi sau server restart.

Web export dùng Compatibility/WebGL 2, không bật threads hoặc extension native. Bản Web tắt bóng đèn hướng để giảm tải và có layout theo chiều màn hình. File WASM khoảng 38 MB trước nén HTTP; nên dùng compression khi chuẩn bị hosting sau này. Có thể xuất release bằng tools/Export-Web.ps1 -Release. Build sinh ra không đưa vào Git.

Chi tiết kiến trúc phòng, giao thức, riêng tư và khôi phục: [server/README.md](server/README.md).

## Chơi thử

Mở project.godot và nhấn F5. Khi bấm TẠO PHÒNG, client desktop kết nối máy chủ đã chạy; nếu chưa có máy chủ ở địa chỉ mặc định ws://127.0.0.1:7000, game tự khởi động dịch vụ phòng cục bộ rồi vào PHÒNG CHỜ. Client desktop khác và browser có thể tham gia bằng mã phòng trên cùng máy. Dịch vụ cục bộ dừng khi đóng tiến trình game đã khởi động nó. Địa chỉ máy chủ tùy chỉnh và bản Web vẫn cần chạy dedicated server riêng.

HOST luôn vào PHÒNG CHỜ trước. Tất cả bấm sẵn sàng, chủ phòng bấm BẮT ĐẦU. Bình thường hỗ trợ 4–7 người; debug cho phép đúng 2 người. Không hỗ trợ 3 người. Host chỉ có quyền quản lý phòng, không được ưu tiên vai trò, máu hoặc lượt.

Mỗi ván server xáo đủ 16 nhân vật, chia mỗi người đúng hai lựa chọn riêng không trùng giữa các người chơi. Giao diện hiện hai thẻ cạnh nhau: chọn tạm rồi xác nhận. Chỉ nhân vật đã xác nhận được công khai ngay; lựa chọn bỏ lại luôn kín. Hết 25 giây, server chọn ngẫu nhiên một trong đúng hai lựa chọn của người đó. Chơi lại xáo lại toàn bộ. Host không được ưu tiên. Cảnh sát trưởng ngẫu nhiên mở lượt sau khi mọi người chọn xong.

Trong Godot, có thể dùng Debug > Customize Run Instances và chạy 4 client kết nối server chung. API host_game/join_game ENet vẫn còn cho test desktop cũ; UI chính không gọi API này. Người chơi browser không cần UDP, VPN hoặc port forwarding.

## Âm thanh

Trong lượt chơi **không có nhạc nền**. AudioManager dùng music_allowed để fade Music bus về im lặng trong 0,4 giây và dừng nguồn phát piano ở mọi phase đang chơi, kể cả reconnect, phản ứng, Đấu súng, Cửa hàng và phán định. Chỉ menu/lobby/chọn nhân vật/kết thúc cho phép nhạc trở lại; cài đặt âm lượng người dùng được giữ nguyên.

Nền trận là gió/phòng thưa, thêm tiếng gỗ hoặc ly rất nhỏ cách nhau 11–24 giây. Đấu súng và phán định Thuốc nổ giảm nền mạnh; an toàn/nổ dừng dây cháy. Weapons và Cards là bus riêng. Colt, Schofield, Remington, Carabine, Winchester, Volcanic có mẫu tiếng riêng; cò súng đi trước phát bắn, Né dùng whoosh/ricochet thay cho va chạm. AudioReworkTest kiểm tra chính sách nhạc và chuyển trạng thái. Không có thay đổi luật gameplay.

Menu chính và menu trong trận có **ÂM THANH**: âm lượng tổng, nhạc, hiệu ứng, môi trường, giao diện và tắt âm; lưu cục bộ trong user://audio_settings.cfg. Web mở âm thanh sau lần chạm/nhấp đầu tiên. Debug có bảng thử âm thanh thu gọn.

AudioManager dùng 16 kênh 2D, 8 kênh 3D và hai lớp nền; giới hạn đồng thời, cooldown, pitch nhẹ, giảm nền tạm thời khi có tiếng quan trọng. Âm gameplay theo sự kiện server có ID, phát cùng hàng đợi trình diễn; refresh state không phát lại hành động. Âm bài kín không phụ thuộc tên/chất/số lá bài. Máy chủ headless không phát âm. 63 tín hiệu tổng hợp gốc ở assets/audio, tái tạo bằng node tools/generate-audio.cjs; xem assets/audio/LICENSE.md. Không dùng âm từ game thương mại. AudioTest kiểm tra asset, bus, trùng sự kiện, giới hạn node, lưu cài đặt và mở khóa touch. Chất lượng phối âm chủ quan cần nghe thử trên thiết bị thật.

## Mỹ thuật nhân vật

16 nhân vật có preset riêng tại resources/characters/visuals/base_visuals.json. CharacterParts lắp thân, mũ, tóc/râu, áo khoác, mặt và phụ kiện theo cùng rig PlayerAvatar; mesh primitive được cache dùng chung. Avatar chỉ đổi theo character_id công khai, giữ nguyên Area3D, metadata người chơi, ghế và các hook shoot/dodge/hit/drink/death. Bản cập nhật mỹ thuật không thay đổi vai trò, kỹ năng hoặc luật.

Chọn nhân vật dùng hai thẻ có chân dung render từ model thật; nhấp cao bồi trên bàn mở thẻ thông tin cùng chân dung. Mỗi portrait dùng SubViewport nhỏ, chỉ render một lần và cập nhật ngắn khi có phản ứng. Không tải artwork thương mại. Nhân vật chưa xác nhận vẫn dùng ngoại hình chung để không lộ hai lựa chọn kín.

Nút dùng WesternButton với phóng nhẹ khi rê chuột và nén nhẹ khi nhấn; thẻ nhân vật bật nổi khi chọn. Bài bay xoay nhẹ rồi hạ phẳng ở đích. Biển hiệu saloon đung đưa cùng bảng tên và có móng ngựa low-poly cạnh tường; các đạo cụ không có collider nhắm mục tiêu. Nhãn thông tin tại cao bồi giữ hai dòng, phần chi tiết chuyển vào thẻ chân dung để không che bàn.

HÌNH ẢNH trong menu chính/menu trong trận có THẤP / VỪA / CAO. Mức THẤP giảm hạt và tắt bóng; VỪA là mặc định Web/mobile; CAO bật bóng desktop. Cả ba mức giữ đầy đủ bài, nhân vật, nhãn và mục tiêu. Lưu tại user://visual_settings.cfg. Chưa đo FPS hoặc xác nhận chất lượng trên điện thoại thật.

CharacterVisualTest kiểm tra 16 preset, tối đa 65 mesh/avatar, hoạt ảnh, giữ collider, chân dung khớp và đồng bộ ngoại hình 7 người. Thêm --capture khi chạy có renderer để xuất tests/artifacts/character-gallery.png và character-table-seven.png. Đây là các ảnh kiểm tra cục bộ, không đưa vào bản phát hành.

## Thao tác trên bàn

- Tay bài là thành phần 2D chính. Bài xếp chồng nhẹ; rê chuột hoặc nhấn giữ khoảng 0,45 giây để xem mô tả đầy đủ. Nhấn giữ rồi thả không tự dùng bài.
- Chạm/nhấp lá Bắn, Hoảng loạn, Cat Balou, Đấu súng hoặc Nhà giam → các cao bồi hợp lệ sáng lên → chạm/nhấp trực tiếp cao bồi. Mũi tên cong xem trước và thông tin khoảng cách/tầm súng chỉ dùng dữ liệu công khai.
- Chạm lại lá đang chọn, nút × HỦY nhỏ cạnh tay, Esc hoặc chuột phải để hủy. Không có hàng nút chọn người chơi hoặc menu tên cho tấn công.
- Khi bị Bắn, Đấu súng, Thổ dân hoặc hấp hối: các lá đáp trả hợp lệ trên chính tay bài sáng lên. Chạm lá để trả lời hoặc chọn CHỊU ĐÒN/KHÔNG CỨU. Janet dùng cùng lá bài vật lý để đổi Bắn/Né theo ngữ cảnh.
- Sid khi thiếu máu có biểu tượng ✚ nhỏ cạnh tay bài. Chạm để chọn/bỏ chọn đúng hai lá, rồi chọn HỒI 1 MÁU. Không có nút kỹ năng lớn thường trực.
- Hoảng loạn/Cat Balou: sau khi chọn cao bồi, chạm vùng TAY KÍN (server chọn ngẫu nhiên, không lộ tên bài), vũ khí hoặc trang bị đang sáng trước ghế.
- Cat Balou có thể bỏ cả Ngựa, Ống nhòm, Thùng, Nhà giam, Thuốc nổ và vũ khí dù tay đối thủ trống. Mỗi lựa chọn trên bàn khóa vào instance_id cụ thể; server từ chối lá đã bị thay thế và không bỏ nhầm bản sao mới. Hiệu lực trang bị mất ngay, kỹ năng bẩm sinh của nhân vật vẫn giữ. DiscardZonesTest kiểm tra riêng các trường hợp này.
- Cửa hàng: bài ngửa xuất hiện giữa bàn; người đang có quyền chọn chạm lá muốn lấy. Những người khác chỉ xem.
- Jesse/Pedro chọn chồng rút/chồng bỏ trực tiếp trên bàn. Jesse cũng có thể chạm vùng tay kín của đối thủ. Rút đầu lượt bình thường hoàn toàn tự động.
- Bỏ bài cuối lượt: hiện BỎ X LÁ; chạm từng lá để bỏ. Server tự chuyển lượt khi đủ giới hạn theo máu.
- KẾT THÚC LƯỢT chỉ xuất hiện gần tay bài trong giai đoạn hành động của bạn.
- Chạm cao bồi khi không nhắm mục tiêu để xem thẻ thông tin: nhân vật, kỹ năng, máu, số bài, vũ khí, trang bị, khoảng cách và vai trò công khai. Chạm chỗ trống để đóng. Vai trò bí mật của đối thủ không hiện.
- Menu ☰ hoặc Esc khi không chọn bài mở TIẾP TỤC / LUẬT CHƠI / RỜI TRẬN. Đồng hồ và trận online vẫn tiếp tục trong menu.
- Nhật ký mặc định chỉ hiện hai hành động gần nhất, có thể mở rộng. Debug chỉ hiện cho host trong bản debug, nằm sau nút DEBUG ở menu tạm dừng.
- Game Over công khai vai trò; chỉ host được CHƠI LẠI hoặc VỀ PHÒNG CHỜ.

## Luật và dữ liệu hiện tại

RoleData hỗ trợ phân bố 4/5/6/7 người. Cảnh sát trưởng công khai, +1 máu; Phó cảnh sát, Tội phạm và Kẻ phản bội được gửi riêng. Vai trò được công khai khi chết và khi hết trận.

CharacterData nạp 16 nhân vật từ resources/characters/characters.json, gồm các kỹ năng rút bài, đổi Bắn/Né, khoảng cách, hai lần Né, hồi máu, nhặt bài khi chết và không giới hạn Bắn. Chọn nhân vật và các lựa chọn kín được gửi riêng cho người sở hữu.

Bộ bài 80 lá có định nghĩa và số lượng trong resources/cards/definitions.json và base_deck.json. Có Bắn, Né, Rượu, Hoảng loạn, Cat Balou, Đấu súng, Nhà giam, năm vũ khí, Thùng, Ngựa, Ống nhòm, Tiếp tế, Cửa hàng, Thổ dân, Thuốc nổ, Súng liên thanh, Quán rượu và Wells Fargo.

Chất/số của cả 80 lá khớp [danh sách chính thức](https://bang.dvgiochi.com/cardslist.php?id=1&lang=en), lưu trong base_manifest.json và base_deck.json. Rank là chuỗi 2–10/J/Q/K/A; hai Tiếp tế 9♠ có ID riêng. Server kiểm tra mọi tổ hợp tên/chất/số và số lượng trước khi bắt đầu; lỗi dữ liệu sẽ chặn ván trong cả bản release. tools/generate_base_data.py đọc manifest này, không tạo chất/số prototype. BaseCorrectionTest có oracle riêng đối chiếu đủ 80 lá, thử dữ liệu hỏng và chơi hết 16 ván tự động, kiểm tra bảo toàn bài sau mỗi hành động.

Tay đầu bằng máu tối đa của nhân vật, gồm thưởng Cảnh sát trưởng. Rút hai mỗi lượt trừ kỹ năng. Bình thường chỉ một lá Bắn trong giai đoạn hành động; dùng sai mục tiêu không tiêu giới hạn. Volcanic/Willy cho bắn nhiều; đáp trả Đấu súng/Thổ dân không tiêu giới hạn. Bắn chuyển đổi của Janet có tiêu giới hạn khi tấn công.

Khoảng cách vòng bỏ qua người chết; Ngựa/Paul và Ống nhòm/Rose cộng dồn. Vũ khí chỉ tăng tầm, không thay khoảng cách. Rượu không hồi khi chỉ còn hai người; sát thương chết người có thể cần nhiều Rượu. Thuốc nổ được phán định trước Nhà giam. Server quản lý hàng đợi phản ứng, giới hạn thời gian và mọi lựa chọn.

## Kiến trúc

- autoload/NetworkManager.gd: facade client/desktop debug, snapshot và sự kiện; WebSocket dùng RoomClient/NetworkTransport, ENet dùng adapter debug.
- server/DedicatedServer.gd và RoomBridge.gd: danh bạ phòng/phiên, host, khôi phục, mỗi phòng có GameManager độc lập dùng chung luật. Server không phải người chơi.
- scripts/network/: WebSocketTransport, ENetTransport, RoomProtocol, NetworkConfig và RoomClient. JSON STATE gửi riêng từng connection với public + private đúng người trong cùng revision.
- autoload/GameManager.gd: match lifecycle, lượt, ý định hợp lệ, máu/chết/thắng và snapshot.
- scripts/game/RoleData.gd, CharacterSelection.gd, AbilityResolver.gd, DrawPhaseResolver.gd, RulesFlow.gd: phân vai, chọn nhân vật, kỹ năng, rút bài, hàng đợi phản ứng/phán định.
- scripts/ui/App.gd: menu/phòng chờ và điều phối. MatchHUD.gd: HUD gọn, tay bài, phản ứng theo ngữ cảnh và menu tạm dừng.
- scripts/ui/HandFan.gd và CardView.gd / scenes/ui/CardUI.tscn: bài xếp chồng, chọn, xem trước và nhấn giữ.
- scripts/ui/TargetingController.gd, TargetingArrow.gd: Area3D ray picking, chuột/chạm, mũi tên và hủy.
- scripts/game/TableView.gd, TableObjects.gd và TableObject.gd: avatar, trạng thái gọn trong 3D, vùng tay kín/trang bị, chồng rút/bỏ và bài Cửa hàng.
- scripts/vfx/TableEffects.gd: bài bay, phán định, chớp súng, −N máu, +1, bụi, BOOM; hiệu ứng tự dọn.
- scripts/game/SaloonRoom.gd, SaloonLantern.gd, scripts/player/PlayerAvatar.gd: môi trường/cao bồi procedural.
- localization/vi.gd: bản dịch. Font hệ thống Segoe UI / Arial / DejaVu Sans và fallback.

UX không thay đổi luật. Client chỉ gửi ID lá bài/người chơi, lựa chọn có request ID hoặc hai ID bài cho Sid. Máy chủ xác thực lại. Vùng tay kín chỉ mang player ID + zone, không chứa lá bài bí mật. Sự kiện VFX chỉ gửi count, player ID và bài đã công khai (bỏ/phán định/Cửa hàng), không truyền tay bài kín hoặc lựa chọn nhân vật.

Dedicated server là bên tin cậy. Host browser chỉ có dữ liệu của một người chơi, không giữ registry luật, tay bài đối thủ hay deck order. Session token 256 bit chỉ gửi cho connection sở hữu, lưu trong sessionStorage của tab và không nằm trong public state. ENet debug vẫn có host desktop tin cậy; đó không phải đường chơi Web.

## Kiểm thử

Các lệnh sau không cần framework ngoài:

    godot --headless --path . tests/RulesTest.tscn
    godot --headless --path . tests/TargetingTest.tscn
    godot --headless --path . tests/GameplayUXTest.tscn
    godot --headless --path . tests/LocalizationTest.tscn
    godot --headless --path . tests/PresentationTest.tscn
    godot --headless --path . tests/VisualEffectsTest.tscn

RulesTest kiểm tra 1.934 điều kiện, gồm 100 lần phân vai cho từng cấu hình 4–7 người, kỹ năng, bài, thưởng/phạt, thắng và riêng tư. GameplayUXTest kiểm tra trực tiếp tay bài, Janet, Sid, lựa chọn trên bàn, menu, preview và ngăn chọn ngoài lượt. TargetingTest dùng sự kiện chuột/chạm thực qua ray picking 3D.

Có thể thêm -- --capture khi chạy không headless với GameplayUXTest, TargetingTest, LocalizationTest hoặc VisualEffectsTest để lưu ảnh cục bộ vào tests/artifacts (bỏ qua bởi Git và Godot importer).

Test nhiều tiến trình ENet trên Windows (cổng 17070):

    powershell -NoProfile -ExecutionPolicy Bypass -File tests/RunNetworkTest.ps1 -Godot "C:/path/to/Godot_v4.7.2-stable_win64_console.exe" -ProcessCount 4

Dùng -ProcessCount 8 để chạy 7 người + kiểm tra người thứ tám bị từ chối. Test phòng chờ hai người trên cổng 7000:

    powershell -NoProfile -ExecutionPolicy Bypass -File tests/RunNetworkTest.ps1 -Godot "C:/path/to/Godot_v4.7.2-stable_win64_console.exe" -TestScene tests/LobbyTest.tscn -ProcessCount 2

Test mạng có thể cần quyền firewall/chạy tiến trình. Test headless trong sandbox có thể in cảnh báo Windows certificate store; game dùng ENet, không dùng TLS. Kết quả PASS và lỗi GDScript cần được xem riêng với cảnh báo môi trường này.

Kiểm thử dedicated server đang chạy và HTTP Web:

    node tests/web/protocol-test.cjs
    node tests/web/room-capacity-test.cjs
    node tests/web/browser-test.cjs
    node tests/web/browser-test.cjs --mobile

Hai test đầu dùng WebSocket thực: tạo/join, cách ly phòng, ready, quyền host, private choices/hands, reconnect, chuyển host, đủ 7 người, từ chối người thứ tám và dọn phòng rỗng. Browser test chạy hai context Edge tách biệt bằng DevTools, không cần npm dependency, thao tác vào UI và 3D thật. --mobile bật giả lập màn hình ngang điện thoại và sự kiện touch, không chỉ gửi chuột. Có thể đặt WWPO_BROWSER để chọn executable Chrome/Edge. Ảnh lưu tests/artifacts/web.

BrowserTestBridge chỉ được bật trong Web DEBUG khi URL có ?e2e=1; dữ liệu quan sát chỉ là dữ liệu browser đang sở hữu/nhìn thấy, không có token, server registry hoặc tay đối thủ. Release build không tạo bridge.

## Giới hạn / TODO

- Đã xuất và chạy bản Web trên Chromium/Edge desktop và giả lập touch. Chưa kiểm thử Firefox, Safari/iPhone hoặc Android thật; vẫn cần kiểm thử thiết bị thực và tab chạy nền.
- Bài nhiều xếp chồng sát hơn; tay bài cực lớn có thể khó chạm chọn, nên bổ sung phân trang/zoom trên màn hình nhỏ.
- Chưa có âm thanh. Có presentation_feedback để gắn âm thanh nút; toàn bộ art/props hiện là mesh và nét vẽ gốc.
- Phán định dùng bài dựng 3D; hiệu ứng không chặn hay kéo dài thời gian xử lý phía server.
- Có reconnect 45 giây và chuyển quyền chủ phòng; chưa có lưu bền qua server restart, spectator joining, save game hay matchmaking. Rời phòng chủ động là bỏ cuộc.
- Các lựa chọn riêng phức tạp như Kit Carlson / Lucky Duke vẫn dùng khung chọn bài riêng; các phản ứng chiến đấu dùng trực tiếp tay bài.
- Chưa đối chiếu chất/số với bộ bài in gốc. Không tuyên bố tương thích chính xác mọi FAQ/phiên bản của trò gốc.
- Chưa triển khai public. Cần TLS termination/WSS, chính sách origin và vận hành trước bước hosting; xem tài liệu server. Bộ bài/nhân vật/luật không được mở rộng trong lần chuyển nền tảng này.

