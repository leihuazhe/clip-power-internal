Gatekeeper 拦截,因为构建是 ad-hoc 签名、没有走公开开发者证书公证。
```
xattr -cr /Applications/ClipPower.app
```


权限清理

```shell
# 只清 Accessibility

tccutil reset Accessibility com.clippower.app

# 只清 Input Monitoring

tccutil reset ListenEvent com.clippower.app

# 两个一起清（连带这个 app 申请过的所有权限）

tccutil reset All com.clippower.app
```