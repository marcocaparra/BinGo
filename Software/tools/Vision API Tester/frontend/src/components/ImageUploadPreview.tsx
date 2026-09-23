import { ChangeEvent, useEffect, useState } from "react";

interface SelectedImage {
  name: string;
  sizeKb: string;
  previewUrl: string;
}

interface ImageUploadPreviewProps {
  onFileSelected: (file: File | null) => void;
}

export function ImageUploadPreview({ onFileSelected }: ImageUploadPreviewProps) {
  const [selectedImage, setSelectedImage] = useState<SelectedImage | null>(null);

  useEffect(() => {
    return () => {
      if (selectedImage) {
        URL.revokeObjectURL(selectedImage.previewUrl);
      }
    };
  }, [selectedImage]);

  function handleImageChange(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0] ?? null;
    onFileSelected(file);

    if (!file) {
      setSelectedImage(null);
      return;
    }

    setSelectedImage((current) => {
      if (current) {
        URL.revokeObjectURL(current.previewUrl);
      }

      return {
        name: file.name,
        sizeKb: (file.size / 1024).toFixed(1),
        previewUrl: URL.createObjectURL(file)
      };
    });
  }

  return (
    <section className="upload-panel">
      <div className="upload-preview">
        {selectedImage ? (
          <>
            <img alt="Preview da imagem selecionada" src={selectedImage.previewUrl} />
            <div className="preview-meta">
              <strong>{selectedImage.name}</strong>
              <span>{selectedImage.sizeKb} KB</span>
            </div>
          </>
        ) : (
          <div className="empty-preview">
            <strong>Nenhuma imagem selecionada</strong>
            <span>Selecione uma imagem local para criar um teste real no backend.</span>
          </div>
        )}
      </div>

      <label className="file-input-label">
        <span>Selecionar imagem</span>
        <input accept="image/*" onChange={handleImageChange} type="file" />
      </label>
    </section>
  );
}
