# SketchUp 모델링 도구

부재별 왕복 없이, **블록 하나 = 모델 하나**로 생성합니다.

## 최초 1회 설치

`drawkit.rb` 를 SketchUp **Plugins 폴더**에 복사한 뒤 SketchUp을 재시작합니다.
(Plugins 폴더의 `.rb` 는 시작 시 자동으로 읽힙니다)

- Windows: `C:\Users\<사용자>\AppData\Roaming\SketchUp\SketchUp 20XX\SketchUp\Plugins`
- macOS: `~/Library/Application Support/SketchUp 20XX/SketchUp/Plugins`

확인: `창 → Ruby 콘솔` 에서 `defined?(DrawKit)` → `"constant"` 가 나오면 완료.

> 설치가 번거로우면 건너뛰어도 됩니다. 그 경우 `drawkit.rb` 내용을 콘솔에 한 번
> 붙여넣으면 그 세션 동안 유효합니다(SketchUp을 끄면 사라집니다).

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

검사 항목: 자동 검증, 중첩 group, 부재명 중복 차단, 크기 0 차단, **오류 시 롤백**,
원기둥 근사 허용오차, 임의 단면 압출, 검증 통과 시에만 저장.

> 좌표·치수·검증 로직만 확인합니다. 면 병합·교차 처리·재질 적용 등 SketchUp 고유
> 동작은 실제 SketchUp에서 확인해야 합니다.
