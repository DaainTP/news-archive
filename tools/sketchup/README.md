# SketchUp 모델링 도구

부재별 왕복 없이, **블록 하나 = 모델 하나**로 생성합니다.

## 최초 1회 설치 (자동)

폴더를 찾을 필요 없습니다. 설치 스크립트가 SketchUp 버전에 맞는 위치를 스스로 찾습니다.

1. `install_drawkit.rb` 를 **다운로드 폴더**(또는 바탕화면)에 저장
2. SketchUp → 상단 메뉴 **[창(Window)] → [Ruby 콘솔(Ruby Console)]**
3. 아래 **한 줄**을 콘솔 입력칸에 붙여넣고 Enter

```ruby
f0=%w[Downloads Desktop 바탕화면].map{|d| File.join(ENV['USERPROFILE']||ENV['HOME'],d,'install_drawkit.rb')}.find{|f| File.exist?(f)}; f0 ? load(f0) : puts("install_drawkit.rb 를 다운로드 폴더나 바탕화면에 두고 다시 실행하세요")
```

이렇게 나오면 완료입니다.

```
설치 완료
  위치: C:/Users/…/AppData/Roaming/SketchUp/SketchUp 2025/SketchUp/Plugins/drawkit.rb
  버전: DrawKit 2.0
```

재시작 없이 바로 쓸 수 있고, SketchUp 을 껐다 켜도 유지됩니다.

> 위 한 줄이 "파일을 찾을 수 없다"고 하면, `install_drawkit.rb` 를 메모장으로 열어
> **내용 전체**를 콘솔에 붙여넣어도 동일하게 설치됩니다.
>
> 설치 자체가 실패하면 스크립트가 시도한 경로 목록을 출력합니다. 그 목록을 그대로
> 알려주시면 해당 환경에 맞게 잡아드립니다.

## 매 작업

1. 도면 PDF 첨부
2. 받은 코드 블록을 **Ruby 콘솔에 붙여넣기** → Enter
3. 출력 확인

```
검증 통과 — 부재 24개가 입력 치수와 일치
```

불일치가 있으면 해당 부재만 다시 만드는 짧은 블록을 받으면 됩니다.

## 명령 4개

| 명령 | 인자 순서 (모두 mm) |
|---|---|
| `box` | 이름, 원점X, Y, Z, 크기W, D, H |
| `cyl` | 이름, 중심X, Y, 바닥Z, 반지름, 높이 |
| `shape` | 이름, 단면 `[[x,y],…]`, 바닥Z, 높이 |
| `group` | 이름 + 블록 (부재 묶기, 중첩 가능) |

옵션: `color: "SteelBlue"`, `layer: "구조"`,
`DrawKit.build("이름", save_to: "C:/sketchup/a.skp")`(검증 통과 시에만 저장),
`verify: false`(검증 생략).

수동 확인용: `DrawKit.audit` — 현재 모델의 전 부재 바운딩박스를 mm 표로 출력.

## 오프라인 자체 점검

SketchUp 없이 로직만 검사합니다. `drawkit.rb` 를 고쳤다면 먼저 돌려보세요.

```bash
ruby tools/sketchup/test/test_drawkit.rb
```

```bash
ruby tools/sketchup/test/test_installer.rb
```

검사 항목 — `test_drawkit.rb`: 자동 검증, 중첩 group, 부재명 중복 차단, 크기 0 차단,
**오류 시 롤백**, 원기둥 근사 허용오차, 임의 단면 압출, 검증 통과 시에만 저장.
`test_installer.rb`: 폴더 자동 탐색, 폴더 없을 때 생성, 쓸 수 없는 경로 회피,
Windows/macOS 경로, 설치 직후 즉시 사용 가능 여부.

> 좌표·치수·검증 로직만 확인합니다. 면 병합·교차 처리·재질 적용 등 SketchUp 고유
> 동작은 실제 SketchUp에서 확인해야 합니다.
