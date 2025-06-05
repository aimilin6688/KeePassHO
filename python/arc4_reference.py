import codecs

class ARC4:
    def __init__(self, key, drop_n=3072):
        """初始化ARC4加密器
        
        Args:
            key: 密钥字节
            drop_n: 初始丢弃字节数
        """
        if not key or len(key) < 1:
            raise ValueError('Key must be at least one byte long')
        if len(key) > 256:
            raise ValueError('Key must be 256 bytes or less')

        # 初始化S盒
        self.S = list(range(256))
        j = 0
        for i in range(256):
            j = (j + self.S[i] + key[i % len(key)]) % 256
            self.S[i], self.S[j] = self.S[j], self.S[i]

        # 丢弃初始字节
        self.i = 0
        self.j = 0
        self.drop(drop_n)

    def drop(self, n):
        """丢弃初始字节以消除弱点
        
        Args:
            n: 要丢弃的字节数
        """
        for _ in range(n):
            self.i = (self.i + 1) % 256
            self.j = (self.j + self.S[self.i]) % 256
            self.S[self.i], self.S[self.j] = self.S[self.j], self.S[self.i]

    def process(self, data):
        """加密/解密数据
        
        Args:
            data: 输入数据字节
        Returns:
            处理后的字节
        """
        result = bytearray(len(data))
        i = self.i
        j = self.j
        S = self.S.copy()

        for k in range(len(data)):
            i = (i + 1) % 256
            j = (j + S[i]) % 256
            S[i], S[j] = S[j], S[i]
            t = (S[i] + S[j]) % 256
            result[k] = data[k] ^ S[t]

        # 保存状态
        self.i = i
        self.j = j
        self.S = S
        return bytes(result)

    def encrypt(self, plaintext):
        """加密字符串
        
        Args:
            plaintext: 明文字符串
        Returns:
            十六进制形式的密文
        """
        data = plaintext.encode('utf-8')
        ciphertext = self.process(data)
        return codecs.encode(ciphertext, 'hex_codec').decode('utf-8')

    def decrypt(self, ciphertext):
        """解密字符串
        
        Args:
            ciphertext: 十六进制形式的密文
        Returns:
            明文字符串
        """
        data = codecs.decode(ciphertext, 'hex_codec')
        plaintext = self.process(data)
        return plaintext.decode('utf-8')