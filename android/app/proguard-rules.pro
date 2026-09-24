# AppProxy ProGuard Rules
# 添加 missing_rules.txt 中要求的规则

# Netty native TLS classes
-dontwarn io.netty.**
-keep class io.netty.** { *; }
-keepattributes Signature,InnerClasses

-dontwarn reactor.**
-keep class reactor.** { *; }

# Java management classes
-dontwarn java.lang.management.ManagementFactory
-dontwarn java.lang.management.RuntimeMXBean

# JFR (Java Flight Recorder) classes
-dontwarn jdk.jfr.Category
-dontwarn jdk.jfr.DataAmount
-dontwarn jdk.jfr.Description
-dontwarn jdk.jfr.Enabled
-dontwarn jdk.jfr.Event
-dontwarn jdk.jfr.FlightRecorder
-dontwarn jdk.jfr.Label
-dontwarn jdk.jfr.MemoryAddress
-dontwarn jdk.jfr.Name

# Log4j classes
-dontwarn org.apache.log4j.Level
-dontwarn org.apache.log4j.Logger
-dontwarn org.apache.log4j.Priority
-dontwarn org.apache.logging.log4j.Level
-dontwarn org.apache.logging.log4j.LogManager
-dontwarn org.apache.logging.log4j.Logger
-dontwarn org.apache.logging.log4j.message.MessageFactory
-dontwarn org.apache.logging.log4j.spi.ExtendedLogger
-dontwarn org.apache.logging.log4j.spi.ExtendedLoggerWrapper

# Bouncy Castle classes
-dontwarn org.bouncycastle.asn1.pkcs.PrivateKeyInfo
-dontwarn org.bouncycastle.openssl.PEMDecryptorProvider
-dontwarn org.bouncycastle.openssl.PEMEncryptedKeyPair
-dontwarn org.bouncycastle.openssl.PEMKeyPair
-dontwarn org.bouncycastle.openssl.PEMParser
-dontwarn org.bouncycastle.openssl.jcajce.JcaPEMKeyConverter
-dontwarn org.bouncycastle.openssl.jcajce.JceOpenSSLPKCS8DecryptorProviderBuilder
-dontwarn org.bouncycastle.openssl.jcajce.JcePEMDecryptorProviderBuilder
-dontwarn org.bouncycastle.operator.InputDecryptorProvider
-dontwarn org.bouncycastle.pkcs.PKCS8EncryptedPrivateKeyInfo

# Conscrypt classes
-dontwarn org.conscrypt.BufferAllocator
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.conscrypt.HandshakeListener

# 保留 tun2socks 相关类（如果需要）
#-keep class com.github.xvfish.tun2socks.** { *; }
-dontwarn reactor.blockhound.integration.BlockHoundIntegration

# libsu：root shell（eBPF 模式用）。AAR 自带 consumer 规则（保留 Initializer/RootService 子类），
# 这里再整体保留一份，避免 release(minify) 下 R8 误裁导致运行期失败
-keep class com.topjohnwu.superuser.** { *; }
-dontwarn com.topjohnwu.superuser.**

# eBPF(sing-box) 模块里用 Gson 反射读写的模型类：release 下必须保留类名/字段名/无参构造，
# 否则报 "Abstract classes can't be instantiated!"（R8 混淆后 Gson 建不出实例）
#   SupportStatus → filesDir/ebpf/support.json（检测结果持久化）
#   UpdateJson    → {下载源}/update.json（版本清单，字段名必须与服务器 JSON 一致）
-keep class cn.ys1231.appproxy.EbpfService.EbpfProxyManager$SupportStatus { *; }
-keep class cn.ys1231.appproxy.EbpfService.EbpfProxyManager$UpdateJson { *; }
