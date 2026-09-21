# SketchUp 모델링 도구 (MCP 없이 사용)

PDF 도면 → 치수표 → Ruby 스크립트 → SketchUp 모델(.skp) 순서로 작업합니다.
MCP 서버(포트 9876)를 쓰지 않으므로 소켓 대기·부재별 왕복 호출이 없습니다.

## 파일

| 파일 | 역할 |
|---|---|
| `drawkit.rb` | mm 단위 변환 + `box` / `extrude` / `cylinder` / `audit` / `verify` / `save_as` 헬퍼 |
| `TEMPLATE_build.rb` | 실제 모델링 스크립트의 뼈대. 치수표만 채워 넣으면 됨 |

## 사용 순서

1. **PDF 첨부** → Claude 가 치수표(ID/부재명/원점/크기/비고)를 만들어 보여줍니다.
2. **치수표 확인** → 사용자가 확정합니다. (읽히지 않는 치수는 추측하지 않고 질문합니다)
3. **스크립트 수령** → `build_프로젝트명.rb` 파일을 받습니다.
4. **실행** → 두 파일(`drawkit.rb`, `build_*.rb`)을 같은 폴더(예: `C:/sketchup/`)에 넣고,
   SketchUp → `창(Window)` → `Ruby 콘솔(Ruby Console)` 에서:

   ```ruby
   load "C:/sketchup/build_프로젝트명.rb"
   ```

5. **검증** → 콘솔에 나오는 `verify` 결과를 확인합니다.
   `검증 통과` 가 뜨면 치수표와 모델이 허용오차(기본 0.5mm) 안에서 일치합니다.
6. **저장** → SketchUp 에서 `파일 → 다른 이름으로 저장`,
   또는 스크립트 마지막 줄의 `DrawKit.save_as("C:/sketchup/프로젝트명.skp")` 주석을 해제합니다.

## 주의

- SketchUp 은 코드 안의 생 숫자를 **인치**로 해석합니다. 반드시 DrawKit 함수를 통해 mm 로 넘기세요.
- 스크립트 전체가 `DrawKit.build` 의 한 트랜잭션으로 묶여 있어, 실행취소(Ctrl+Z) 한 번으로 전부 되돌아갑니다.
- 실행 중 오류가 나면 모델은 자동으로 이전 상태로 롤백됩니다(`abort_operation`).

## 오프라인 자체 점검

SketchUp 없이 `drawkit.rb` 로직만 검사하는 테스트가 있습니다.
`test/su_stub.rb` 가 SketchUp API를 흉내 내므로, 규칙을 고칠 때마다 먼저 여기서 확인하세요.

```bash
ruby tools/sketchup/test/test_drawkit.rb
```

검사 항목: mm 환산, 박스/원기둥 바운딩박스, **중첩(assembly) 부재 탐색**,
치수 불일치·부재 누락·**이름 중복** 검출, 예외 시 롤백, 저장 경로.

> 이 테스트는 좌표·치수·검증 로직만 확인합니다. SketchUp 고유 동작(면 병합,
> 교차 처리, 재질 적용 결과 등)은 실제 SketchUp에서 확인해야 합니다.
