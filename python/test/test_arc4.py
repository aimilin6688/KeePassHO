from arc4_reference import ARC4
import codecs

def test_arc4_consistency():
    # 使用与HarmonyOS测试相同的向量
    key = 'PythonKey123'.encode('utf-8')
    plaintext = 'CrossLangTest'.encode('utf-8')
    
    # 创建ARC4实例（包含3072字节初始丢弃）
    cipher = ARC4(key)
    
    # 加密
    ciphertext = cipher.process(plaintext)
    print(f"Ciphertext: {codecs.encode(ciphertext, 'hex_codec').decode('utf-8')}")
    
    # 解密验证
    cipher = ARC4(key)  # 重置状态
    decrypted = cipher.process(ciphertext)
    print(f"Decrypted: {decrypted.decode('utf-8')}")
    
    assert decrypted.decode('utf-8') == 'CrossLangTest', "Decryption failed!"
    print("All tests passed!")

def test_arc4_consistency2(key, keyplain):
    # 使用与HarmonyOS测试相同的向量
    key = key.encode('utf-8')
    plaintext = keyplain.encode('utf-8')

    # 创建ARC4实例（包含3072字节初始丢弃）
    cipher = ARC4(key)

    # 加密
    ciphertext = cipher.process(plaintext)
    print(f"Ciphertext: {codecs.encode(ciphertext, 'hex_codec').decode('utf-8')}")

    # 解密验证
    cipher = ARC4(key)  # 重置状态
    decrypted = cipher.process(ciphertext)
    print(f"Decrypted: {decrypted.decode('utf-8')}")

    assert decrypted.decode('utf-8') == keyplain, "Decryption failed!"
    print("All tests passed!")

if __name__ == '__main__':
    test_arc4_consistency()
    test_arc4_consistency2('shortKey', 'Z')
    test_arc4_consistency2('mySecretKey', 'Hello World')
    test_arc4_consistency2('p@ssw0rd!', 'Data123!abc')
    test_arc4_consistency2('ARC4@2023', '加密测试')