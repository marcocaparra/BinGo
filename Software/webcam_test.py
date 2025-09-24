import cv2

def main():
    cap = cv2.VideoCapture(0)  # 0 = primeira webcam. se não abrir, tente 1,2,...
    if not cap.isOpened():
        print("Erro: não consegui abrir a webcam. Verifique índice/permissões.")
        return

    print("Pressione 'q' para sair.")
    while True:
        ret, frame = cap.read()
        if not ret:
            print("Falha ao capturar frame.")
            break
        cv2.imshow("Webcam - teste", frame)
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()