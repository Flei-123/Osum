(module
 (import "wasi_snapshot_preview1" "fd_write" (func $fw (param i32 i32 i32 i32) (result i32)))
 (memory 1) (export "memory" (memory 0))
 (data (i32.const 100) "hi\n")
 (func (export "_start")
  (i32.store (i32.const 0) (i32.const 100))
  (i32.store (i32.const 4) (i32.const 3))
  (drop (call $fw (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 20)))))
