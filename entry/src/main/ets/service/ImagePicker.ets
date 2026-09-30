import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { Attachment } from '../model/Types';
import { Logger } from '../common/Logger';
import { Utils } from '../common/Utils';

/**
 * 图片选择 + 等比压缩 + base64 编码
 * 为视觉模型（DeepSeek-Flash / GPT-4o / GPT-5 等）准备 image_url 内容分段
 */
export class ImagePicker {
  /** 最长边上限，控制请求体体积 */
  private static readonly MAX_SIDE: number = 1280;

  static async pick(maxCount: number): Promise<Attachment[]> {
    const out: Attachment[] = [];
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = maxCount;
    const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
    const uris: string[] = result.photoUris;
    if (uris === undefined || uris === null) {
      return out;
    }
    for (let i = 0; i < uris.length; i++) {
      const a: Attachment | null = await ImagePicker.encode(uris[i]);
      if (a !== null) {
        out.push(a);
      }
    }
    return out;
  }

  private static async encode(uri: string): Promise<Attachment | null> {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const src: image.ImageSource = image.createImageSource(file.fd);
      const info: image.ImageInfo = await src.getImageInfo();
      let w: number = info.size.width;
      let h: number = info.size.height;
      const maxSide: number = Math.max(w, h);
      if (maxSide > ImagePicker.MAX_SIDE) {
        const k: number = ImagePicker.MAX_SIDE / maxSide;
        w = Math.max(1, Math.round(w * k));
        h = Math.max(1, Math.round(h * k));
      }
      const pm: image.PixelMap = await src.createPixelMap({ desiredSize: { width: w, height: h } });
      const packer: image.ImagePacker = image.createImagePacker();
      const buf: ArrayBuffer = await packer.packToData(pm, { format: 'image/jpeg', quality: 84 });
      const b64: string = new util.Base64Helper().encodeToStringSync(new Uint8Array(buf));
      const a: Attachment = new Attachment();
      a.id = Utils.uid('att');
      a.name = 'image_' + a.id + '.jpg';
      a.mime = 'image/jpeg';
      a.size = buf.byteLength;
      a.dataUrl = 'data:image/jpeg;base64,' + b64;
      await src.release();
      await pm.release();
      packer.release();
      return a;
    } catch (e) {
      const err = e as Error;
      Logger.error('encode image failed: ' + err.message);
      return null;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (e2) {
        }
      }
    }
  }
}
